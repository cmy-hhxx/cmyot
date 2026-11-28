//
//  CotLocalDatabase+MediaBlobs.swift
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

import CryptoKit
import Foundation
import SQLite3

/// Logical namespace partitioning disk-backed visual assets stored inside SQLite `media_blobs`.
nonisolated enum MediaBlobNamespace: String, CaseIterable, Sendable {
    
    case mediaAvatar = "media_avatar"
    case mediaBackground = "media_background"
    case sticker = "sticker"
    case wallpaper = "wallpaper"
    case appIcon = "app_icon"
    case inlineImage = "inline_image"
}


/// Lightweight metadata row from `media_blobs` (without loading binary `data` payload).
nonisolated struct MediaBlobMetadata: Equatable, Sendable {
    
    let blobKey: String
    let namespace: String
    let relativePath: String
    let sha256: String
    let bytes: Int
    let updatedAt: Double
}


/// Deterministic path sanitizer and key builder preventing traversal outside asset root directories.
nonisolated enum MediaBlobPathSanitizer {
    
    static func sanitizeRelativePath(_ raw: String) -> String? {
        if raw.isEmpty || raw.contains("\0") || raw.contains("\\") || raw.hasPrefix("/") {
            return nil
        }
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var clean: [String] = []
        clean.reserveCapacity(parts.count)
        for part in parts {
            let segment = String(part)
            if segment.isEmpty || segment == "." || segment == ".." {
                return nil
            }
            clean.append(segment)
        }
        return clean.joined(separator: "/")
    }
    
    
    static func safeDestinationURL(rootDirectory: URL, relativePath: String) -> URL? {
        guard let clean = Self.sanitizeRelativePath(relativePath) else { return nil }
        let standardizedRoot = rootDirectory.standardizedFileURL
        let candidate = standardizedRoot.appending(path: clean).standardizedFileURL
        let rootPrefix = standardizedRoot.path.hasSuffix("/") ? standardizedRoot.path : standardizedRoot.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else { return nil }
        return candidate
    }
    
    
    static func blobKey(namespace: MediaBlobNamespace, relativePath: String) -> String {
        "\(namespace.rawValue):\(relativePath)"
    }
    
    
    static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}


extension CotLocalDatabase {
    
    func createMediaBlobsTableIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS media_blobs (
            blob_key TEXT PRIMARY KEY,
            namespace TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            sha256 TEXT NOT NULL DEFAULT '',
            bytes INTEGER NOT NULL DEFAULT 0,
            data BLOB NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_media_blobs_namespace ON media_blobs(namespace);
        """
        self.executeSQL(sql)
    }
    
    
    func upsertMediaBlob(
        namespace: MediaBlobNamespace,
        relativePath: String,
        data: Data,
        sha256: String? = nil
    ) {
        guard !data.isEmpty,
              let db = self.db,
              let cleanPath = MediaBlobPathSanitizer.sanitizeRelativePath(relativePath)
        else { return }
        
        let key = MediaBlobPathSanitizer.blobKey(namespace: namespace, relativePath: cleanPath)
        let resolvedSHA = (sha256?.isEmpty == false) ? sha256! : MediaBlobPathSanitizer.sha256Hex(data)
        let now = Date().timeIntervalSince1970
        let sql = """
        INSERT INTO media_blobs (blob_key, namespace, relative_path, sha256, bytes, data, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(blob_key) DO UPDATE SET
            namespace = excluded.namespace,
            relative_path = excluded.relative_path,
            sha256 = excluded.sha256,
            bytes = excluded.bytes,
            data = excluded.data,
            updated_at = excluded.updated_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, key, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, namespace.rawValue, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 3, cleanPath, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 4, resolvedSHA, -1, self.transientDestructor)
            sqlite3_bind_int64(stmt, 5, Int64(data.count))
            data.withUnsafeBytes { rawBuffer in
                sqlite3_bind_blob(stmt, 6, rawBuffer.baseAddress, Int32(data.count), self.transientDestructor)
            }
            sqlite3_bind_double(stmt, 7, now)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
    }
    
    
    func fetchMediaBlobData(namespace: MediaBlobNamespace, relativePath: String) -> Data? {
        guard let db = self.db,
              let cleanPath = MediaBlobPathSanitizer.sanitizeRelativePath(relativePath)
        else { return nil }
        
        let key = MediaBlobPathSanitizer.blobKey(namespace: namespace, relativePath: cleanPath)
        let sql = "SELECT data FROM media_blobs WHERE blob_key = ? LIMIT 1;"
        var stmt: OpaquePointer?
        var result: Data?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, key, -1, self.transientDestructor)
            if sqlite3_step(stmt) == SQLITE_ROW {
                let byteCount = Int(sqlite3_column_bytes(stmt, 0))
                if byteCount > 0, let ptr = sqlite3_column_blob(stmt, 0) {
                    result = Data(bytes: ptr, count: byteCount)
                }
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    
    func fetchMediaBlobMetadata(in namespace: MediaBlobNamespace) -> [MediaBlobMetadata] {
        guard let db = self.db else { return [] }
        let sql = """
        SELECT blob_key, namespace, relative_path, sha256, bytes, updated_at
        FROM media_blobs
        WHERE namespace = ?;
        """
        var stmt: OpaquePointer?
        var out: [MediaBlobMetadata] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, namespace.rawValue, -1, self.transientDestructor)
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let keyCStr = sqlite3_column_text(stmt, 0),
                      let nsCStr = sqlite3_column_text(stmt, 1),
                      let pathCStr = sqlite3_column_text(stmt, 2)
                else { continue }
                let sha = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
                out.append(MediaBlobMetadata(
                    blobKey: String(cString: keyCStr),
                    namespace: String(cString: nsCStr),
                    relativePath: String(cString: pathCStr),
                    sha256: sha,
                    bytes: Int(sqlite3_column_int64(stmt, 4)),
                    updatedAt: sqlite3_column_double(stmt, 5)
                ))
            }
        }
        sqlite3_finalize(stmt)
        return out
    }
    
    
    func deleteMediaBlob(namespace: MediaBlobNamespace, relativePath: String) {
        guard let db = self.db,
              let cleanPath = MediaBlobPathSanitizer.sanitizeRelativePath(relativePath)
        else { return }
        let key = MediaBlobPathSanitizer.blobKey(namespace: namespace, relativePath: cleanPath)
        let sql = "DELETE FROM media_blobs WHERE blob_key = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, key, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    func pruneMediaBlobs(in namespace: MediaBlobNamespace, keepingRelativePaths validPaths: Set<String>) {
        let sanitizedValid = Set(validPaths.compactMap(MediaBlobPathSanitizer.sanitizeRelativePath))
        let existing = self.fetchMediaBlobMetadata(in: namespace)
        let staleKeys = existing
            .filter { !sanitizedValid.contains($0.relativePath) }
            .map(\.blobKey)
        guard !staleKeys.isEmpty, let db = self.db else { return }
        
        self.withTransaction {
            let sql = "DELETE FROM media_blobs WHERE blob_key = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                for key in staleKeys {
                    sqlite3_reset(stmt)
                    sqlite3_clear_bindings(stmt)
                    sqlite3_bind_text(stmt, 1, key, -1, self.transientDestructor)
                    sqlite3_step(stmt)
                }
            }
            sqlite3_finalize(stmt)
        }
    }
    
    
    func syncDiskFilesToMediaBlobs(
        namespace: MediaBlobNamespace,
        rootDirectory: URL,
        expectedRelativePaths: [String],
        pruneUnreferenced: Bool = true
    ) {
        let existingList = self.fetchMediaBlobMetadata(in: namespace)
        var existingByPath: [String: MediaBlobMetadata] = [:]
        existingByPath.reserveCapacity(existingList.count)
        for item in existingList {
            existingByPath[item.relativePath] = item
        }
        
        var expectedSet: Set<String> = []
        expectedSet.reserveCapacity(expectedRelativePaths.count)
        let fm = FileManager.default
        
        self.withTransaction {
            for rawPath in expectedRelativePaths {
                guard let cleanPath = MediaBlobPathSanitizer.sanitizeRelativePath(rawPath) else { continue }
                expectedSet.insert(cleanPath)
                guard let fileURL = MediaBlobPathSanitizer.safeDestinationURL(rootDirectory: rootDirectory, relativePath: cleanPath),
                      fm.fileExists(atPath: fileURL.path(percentEncoded: false))
                else { continue }
                
                let attrs = try? fm.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
                let diskSize = (attrs?[.size] as? NSNumber)?.intValue ?? -1
                let diskMtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                
                if let existing = existingByPath[cleanPath],
                   existing.bytes == diskSize,
                   diskMtime <= existing.updatedAt + 0.5
                {
                    continue
                }
                if let data = try? Data(contentsOf: fileURL), !data.isEmpty {
                    self.upsertMediaBlob(namespace: namespace, relativePath: cleanPath, data: data)
                }
            }
        }
        
        if pruneUnreferenced {
            self.pruneMediaBlobs(in: namespace, keepingRelativePaths: expectedSet)
        }
    }
    
    
    @discardableResult
    func restoreMediaBlobsToDisk(
        namespace: MediaBlobNamespace,
        rootDirectory: URL,
        allowedRelativePaths: Set<String>? = nil,
        overwriteMismatched: Bool = false
    ) -> Int {
        let metadata = self.fetchMediaBlobMetadata(in: namespace)
        guard !metadata.isEmpty else { return 0 }
        
        let allowedSanitized: Set<String>? = allowedRelativePaths.map { paths in
            Set(paths.compactMap(MediaBlobPathSanitizer.sanitizeRelativePath))
        }
        let fm = FileManager.default
        var restoredCount = 0
        
        for meta in metadata {
            if let allowedSanitized, !allowedSanitized.contains(meta.relativePath) {
                continue
            }
            guard let destURL = MediaBlobPathSanitizer.safeDestinationURL(
                rootDirectory: rootDirectory,
                relativePath: meta.relativePath
            ) else { continue }
            
            let destPath = destURL.path(percentEncoded: false)
            if fm.fileExists(atPath: destPath) {
                guard overwriteMismatched else { continue }
                let attrs = try? fm.attributesOfItem(atPath: destPath)
                let diskSize = (attrs?[.size] as? NSNumber)?.intValue ?? -1
                if diskSize == meta.bytes {
                    if meta.sha256.isEmpty {
                        continue
                    }
                    if let diskData = try? Data(contentsOf: destURL),
                       MediaBlobPathSanitizer.sha256Hex(diskData) == meta.sha256
                    {
                        continue
                    }
                }
            }
            
            guard let data = self.fetchMediaBlobData(namespace: namespace, relativePath: meta.relativePath) else {
                continue
            }
            do {
                try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destURL, options: .atomic)
                restoredCount += 1
            } catch {
                continue
            }
        }
        return restoredCount
    }
    
    
    @discardableResult
    func ensureDiskFileFromMediaBlob(
        namespace: MediaBlobNamespace,
        relativePath: String,
        rootDirectory: URL
    ) -> URL? {
        guard let destURL = MediaBlobPathSanitizer.safeDestinationURL(
            rootDirectory: rootDirectory,
            relativePath: relativePath
        ) else { return nil }
        
        let fm = FileManager.default
        if fm.fileExists(atPath: destURL.path(percentEncoded: false)) {
            return destURL
        }
        guard let data = self.fetchMediaBlobData(namespace: namespace, relativePath: relativePath) else {
            return nil
        }
        do {
            try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destURL, options: .atomic)
            return destURL
        } catch {
            return nil
        }
    }
    
    
    func syncReferencedInlineImagesToDatabase(globalFolder: URL? = nil) {
        let folder = globalFolder ?? Self.defaultGlobalInlineImagesDirectory
        var referencedFiles: Set<String> = []
        
        var allContents: [String] = []
        if let db = self.db {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT content FROM documents;", -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let cStr = sqlite3_column_text(stmt, 0) {
                        allContents.append(String(cString: cStr))
                    }
                }
            }
            sqlite3_finalize(stmt)
        }
        if allContents.isEmpty {
            allContents = (self.documents + self.trashedDocuments).map(\.content)
        }
        
        for content in allContents {
            let nsStr = content as NSString
            guard nsStr.length > 0 else { continue }
            let tokens = PlainTextInlineImageStore.shared.findTokens(
                in: nsStr,
                range: NSRange(location: 0, length: nsStr.length)
            )
            for token in tokens {
                if let clean = MediaBlobPathSanitizer.sanitizeRelativePath(token.identifier) {
                    referencedFiles.insert(clean)
                }
            }
        }
        
        let fm = FileManager.default
        var pathsToSync = referencedFiles.filter { filename in
            let url = folder.appending(path: filename)
            return fm.fileExists(atPath: url.path(percentEncoded: false))
        }
        if !pathsToSync.isEmpty {
            let transformsURL = folder.appending(path: "image-transforms.json")
            if fm.fileExists(atPath: transformsURL.path(percentEncoded: false)) {
                pathsToSync.insert("image-transforms.json")
            }
        }
        self.syncDiskFilesToMediaBlobs(
            namespace: .inlineImage,
            rootDirectory: folder,
            expectedRelativePaths: Array(pathsToSync),
            pruneUnreferenced: true
        )
    }
    
    
    func restoreInlineImagesFromDatabase(globalFolder: URL? = nil, overwriteMismatched: Bool = false) {
        let folder = globalFolder ?? Self.defaultGlobalInlineImagesDirectory
        _ = self.restoreMediaBlobsToDisk(
            namespace: .inlineImage,
            rootDirectory: folder,
            allowedRelativePaths: nil,
            overwriteMismatched: overwriteMismatched
        )
    }
    
    
    private static var defaultGlobalInlineImagesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appending(path: "Cot/InlineImages", directoryHint: .isDirectory)
    }
}
