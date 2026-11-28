//
//  MigrationArchiveTests.swift
//
//  Tests
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
import SQLite3
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct MigrationArchiveTests {
    
    @Test func compressedArchiveRoundTripsConfigsBotsBlobsAndSidecarsWhilePruningCaches() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "cot_m3_roundtrip_\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        
        let srcDir = root.appending(path: "src", directoryHint: .isDirectory)
        let dstDir = root.appending(path: "dst", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)
        
        let srcDB = CotLocalDatabase(customURL: srcDir.appending(path: "cot.sqlite3"))
        let srcRoots = Self.makeSidecarRoots(under: srcDir.appending(path: "AppSupport", directoryHint: .isDirectory))
        try Self.createSidecarDirs(srcRoots)
        
        // 1. Write user configs, bots config JSON, custom bot payload, and regenerable cache key
        srcDB.set("凛", forKey: CotLocalDatabase.ConfigKey.butlerName)
        let botCfgJSON = """
        {"butler":{"isEnabled":true,"modelOverride":"claude-sonnet-4","customPersona":"冷静高效的桌面管家"}}
        """
        srcDB.set(botCfgJSON, forKey: CotLocalDatabase.ConfigKey.aiBotsConfigJSON)
        
        let customBotJSON = """
        {"id":"custom_m3test","name":"研究助手","nickname":"研研","modelOverride":"deepseek-reasoner","personaPrompt":"专注学术与架构分析","baseline":"calm","preferredStickerCategories":[],"accentHex":"#2F6BFF","isEnabled":true,"createdAt":1700000000}
        """
        srcDB.upsertCustomBotPayload(id: "custom_m3test", json: customBotJSON, createdAt: 1700000000, updatedAt: 1700000100)
        
        srcDB.set("{\"cached\":true}", forKey: CotLocalDatabase.ConfigKey.aiHotNewsCacheJSON)
        srcDB.set("{\"tips\":[]}", forKey: CotLocalDatabase.ConfigKey.proactiveDailyTipsStateJSON)
        
        // 2. Write a large (>128 KB) compressible opaque PNG blob in wallpaper namespace
        let largeWallpaperData = try Self.makeLargeNoisyOpaquePNG(width: 1400, height: 900)
        #expect(largeWallpaperData.count > 128 * 1024)
        srcDB.upsertMediaBlob(namespace: .wallpaper, relativePath: "custom-wp.png", data: largeWallpaperData)
        
        // Also write a sticker blob (must NOT be recompressed)
        let stickerData = try Self.makeLargeNoisyOpaquePNG(width: 400, height: 400)
        srcDB.upsertMediaBlob(namespace: .sticker, relativePath: "cat.png", data: stickerData)
        
        // 3. Write sidecar files (KeyBindings plist + custom theme)
        let plistData = Data("<plist><array/></plist>".utf8)
        try plistData.write(to: srcRoots.keyBindings.appending(path: "Shortcuts.plist"))
        let themeData = Data("{\"name\":\"Studio Custom\"}".utf8)
        try themeData.write(to: srcRoots.themes.appending(path: "Studio Custom.cottheme"))
        
        // 4. Export .cotbackup archive
        let archiveURL = root.appending(path: "export.cotbackup")
        let exportResult = try await MigrationArchiveService.exportArchive(
            from: srcDB,
            to: archiveURL,
            sidecarRoots: srcRoots
        )
        #expect(FileManager.default.fileExists(atPath: archiveURL.path(percentEncoded: false)))
        #expect(exportResult.stats.recompressedBlobCount >= 1)
        #expect(exportResult.stats.reclaimedBlobBytes > 0)
        #expect(exportResult.stats.slimmedSQLiteBytes < exportResult.stats.originalSQLiteBytes)
        #expect(exportResult.stats.sidecarCount == 2)
        
        // 5. Import into clean destination database & empty sidecars
        let dstDB = CotLocalDatabase(customURL: dstDir.appending(path: "cot.sqlite3"))
        let dstRoots = Self.makeSidecarRoots(under: dstDir.appending(path: "AppSupport", directoryHint: .isDirectory))
        let backupDir = dstDir.appending(path: "Backups", directoryHint: .isDirectory)
        
        let importResult = try await MigrationArchiveService.importArchive(
            from: archiveURL,
            into: dstDB,
            sidecarRoots: dstRoots,
            backupDirectory: backupDir
        )
        #expect(!importResult.wasLegacySQLite)
        #expect(importResult.restoredSidecarCount == 2)
        #expect(FileManager.default.fileExists(atPath: importResult.rollbackSnapshotURL.path(percentEncoded: false)))
        
        // 6. Assert data parity, cache pruning, blob shrinking, and sidecars
        #expect(dstDB.string(forKey: CotLocalDatabase.ConfigKey.butlerName) == "凛")
        #expect(dstDB.string(forKey: CotLocalDatabase.ConfigKey.aiBotsConfigJSON) == botCfgJSON)
        #expect(dstDB.fetchCustomBotPayloads().contains(where: { $0.contains("custom_m3test") }))
        
        #expect(dstDB.string(forKey: CotLocalDatabase.ConfigKey.aiHotNewsCacheJSON).isEmpty)
        #expect(dstDB.string(forKey: CotLocalDatabase.ConfigKey.proactiveDailyTipsStateJSON).isEmpty)
        
        let restoredWallpaperData = try #require(dstDB.fetchMediaBlobData(namespace: .wallpaper, relativePath: "custom-wp.png"))
        #expect(restoredWallpaperData.count < largeWallpaperData.count)
        let wpMeta = try #require(dstDB.fetchMediaBlobMetadata(in: .wallpaper).first)
        #expect(wpMeta.bytes == restoredWallpaperData.count)
        #expect(wpMeta.sha256 == MigrationArchiveService.sha256Hex(restoredWallpaperData))
        
        let restoredStickerData = try #require(dstDB.fetchMediaBlobData(namespace: .sticker, relativePath: "cat.png"))
        #expect(restoredStickerData == stickerData)
        
        #expect((try? Data(contentsOf: dstRoots.keyBindings.appending(path: "Shortcuts.plist"))) == plistData)
        #expect((try? Data(contentsOf: dstRoots.themes.appending(path: "Studio Custom.cottheme"))) == themeData)
    }
    
    
    @Test func legacySQLiteImportRemainsSupportedAndCorruptArchiveLeavesDestinationUntouched() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "cot_m3_legacy_\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        
        let srcDB = CotLocalDatabase(customURL: root.appending(path: "src.sqlite3"))
        srcDB.set("旧版迁移总管", forKey: CotLocalDatabase.ConfigKey.butlerName)
        let legacyURL = root.appending(path: "legacy.sqlite3")
        try srcDB.exportDatabase(to: legacyURL)
        
        let dstDB = CotLocalDatabase(customURL: root.appending(path: "dst.sqlite3"))
        let dstRoots = Self.makeSidecarRoots(under: root.appending(path: "AppSupport", directoryHint: .isDirectory))
        let backupDir = root.appending(path: "Backups", directoryHint: .isDirectory)
        
        let legacyResult = try await MigrationArchiveService.importArchive(
            from: legacyURL,
            into: dstDB,
            sidecarRoots: dstRoots,
            backupDirectory: backupDir
        )
        #expect(legacyResult.wasLegacySQLite)
        #expect(dstDB.string(forKey: CotLocalDatabase.ConfigKey.butlerName) == "旧版迁移总管")
        
        let corruptURL = root.appending(path: "corrupt.cotbackup")
        try Data("not-a-valid-archive".utf8).write(to: corruptURL)
        var didThrow = false
        do {
            _ = try await MigrationArchiveService.importArchive(
                from: corruptURL,
                into: dstDB,
                sidecarRoots: dstRoots,
                backupDirectory: backupDir
            )
        } catch {
            didThrow = true
        }
        #expect(didThrow)
        #expect(dstDB.string(forKey: CotLocalDatabase.ConfigKey.butlerName) == "旧版迁移总管")
    }
    
    
    private static func makeSidecarRoots(under base: URL) -> MigrationArchiveSidecarRoots {
        MigrationArchiveSidecarRoots(
            keyBindings: base.appending(path: "KeyBindings", directoryHint: .isDirectory),
            themes: base.appending(path: "Themes", directoryHint: .isDirectory),
            syntaxes: base.appending(path: "Syntaxes", directoryHint: .isDirectory),
            replacements: base.appending(path: "Replacements", directoryHint: .isDirectory)
        )
    }
    
    
    private static func createSidecarDirs(_ roots: MigrationArchiveSidecarRoots) throws {
        for (_, url) in roots.namedDirectories {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    
    private static func makeLargeNoisyOpaquePNG(width: Int, height: Int) throws -> Data {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * height)
        var state: UInt64 = 0x123456789ABCDEF0
        for y in 0..<height {
            for x in 0..<width {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let idx = y * bytesPerRow + x * 4
                pixels[idx] = UInt8((state >> 16) & 0xFF)
                pixels[idx + 1] = UInt8((state >> 24) & 0xFF)
                pixels[idx + 2] = UInt8((state >> 32) & 0xFF)
                pixels[idx + 3] = 255
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ),
              let cgImage = ctx.makeImage()
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}
