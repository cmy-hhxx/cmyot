//
//  MediaLibraryDatabaseMigrationTests.swift
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
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct MediaLibraryDatabaseMigrationTests {
    
    @Test func crossDeviceFullMediaLibraryMigrationPreservesAllAssetsAndPixels() async throws {
        let rootA = Self.makeTempDir("deviceA")
        let rootB = Self.makeTempDir("deviceB")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        
        let dbA = CotLocalDatabase(customURL: rootA.appending(path: "cot.sqlite3"))
        let mediaA = UserMediaLibraryStore(database: dbA, storageDirectory: rootA.appending(path: "MediaLibrary", directoryHint: .isDirectory))
        let stickersA = CotStickerLibraryStore(database: dbA, stickersDirectory: rootA.appending(path: "MediaLibrary/stickers", directoryHint: .isDirectory))
        let wallpapersA = WallpaperManager(database: dbA, storageDirectory: rootA.appending(path: "Wallpapers", directoryHint: .isDirectory))
        let iconA = AppIconManager(database: dbA, storageDirectory: rootA.appending(path: "CustomAppIcon", directoryHint: .isDirectory))
        let heroA = DashboardHeroCoverStore(database: dbA)
        let inlineDirA = rootA.appending(path: "InlineImages", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inlineDirA, withIntermediateDirectories: true)
        
        // 1. Populate Device A media library (avatar + crop edit with original, background + board + wallpaper + hero)
        let avFile = rootA.appending(path: "src_avatar.png")
        let bgFile = rootA.appending(path: "src_bg.jpg")
        let customWpFile = rootA.appending(path: "src_custom_wp.jpg")
        let stickerFile = rootA.appending(path: "src_sticker.png")
        try Self.writeSolidPNG(to: avFile, size: NSSize(width: 120, height: 120), color: .systemPink)
        try Self.writeSolidJPEG(to: bgFile, size: NSSize(width: 400, height: 240), color: .systemTeal)
        try Self.writeSolidJPEG(to: customWpFile, size: NSSize(width: 400, height: 240), color: .systemRed)
        try Self.writeSolidPNG(to: stickerFile, size: NSSize(width: 96, height: 96), color: .systemOrange)
        
        let avAsset = try #require(mediaA.addImage(from: avFile, kind: .avatar, customTitle: "主头像").asset)
        let editedAv = try #require(mediaA.updateAssetEdit(
            id: avAsset.id,
            kind: .avatar,
            title: "裁切头像",
            editSpec: UserMediaEditSpec(scale: 1.6, panX: 0.2, panY: -0.1, aspectPreset: .square, quarterTurns: 1, flipHorizontal: true),
            wallpaperManager: wallpapersA
        ))
        let bgAsset = try #require(mediaA.addImage(from: bgFile, kind: .background, customTitle: "海雾背景").asset)
        mediaA.setBoardBackground(assetID: bgAsset.id, for: .market, opacity: 0.34, blurRadius: 8)
        #expect(mediaA.applyBackgroundToEditorWallpaper(assetID: bgAsset.id, wallpaperManager: wallpapersA))
        #expect(mediaA.applyBackgroundToDashboardHero(assetID: bgAsset.id, heroStore: heroA))
        heroA.focalX = 0.25
        heroA.focalY = 0.72
        heroA.fitMode = .fit
        heroA.blurStyle = .frosted
        
        // 2. Standalone custom wallpaper & custom App Icon
        let standaloneWp = try #require(wallpapersA.saveCustomWallpaper(from: customWpFile, title: "朱红壁纸"))
        wallpapersA.selectWallpaper(id: standaloneWp.id, enableIfDisabled: true)
        let iconImg = try #require(NSImage(contentsOf: stickerFile))
        #expect(iconA.saveCustomImage(iconImg))
        
        // 3. Stickers with semantics, favorite, use count
        let stkImport = await stickersA.importFiles([stickerFile], defaultCategory: "cat")
        #expect(stkImport.addedCount == 1)
        let stk = try #require(stickersA.stickers.first)
        stickersA.updateSemantics(id: stk.id, category: "cat", ocrText: "摸鱼", meaning: "摸鱼猫猫", moods: ["摸鱼"], tags: ["猫"])
        stickersA.toggleFavorite(id: stk.id)
        stickersA.recordUse(id: stk.id)
        let stickerBytesA = try #require(stickersA.imageData(for: stk.id)?.data)
        
        // 4. Untitled document inline image + transforms
        let inlineName = "img-migrated.png"
        try Self.writeSolidPNG(to: inlineDirA.appending(path: inlineName), size: NSSize(width: 80, height: 60), color: .systemBlue)
        try Data("{\"img-migrated.png\":{\"scale\":1.5}}".utf8).write(to: inlineDirA.appending(path: "image-transforms.json"))
        dbA.saveDocument(id: "doc-inline", title: "图文笔记", filePath: nil, syntax: "Markdown", content: "测试图片\n⟦🖼 \(inlineName)⟧\n完成")
        dbA.syncReferencedInlineImagesToDatabase(globalFolder: inlineDirA)
        
        let backupURL = rootA.appending(path: "portable_backup.sqlite3")
        try dbA.exportDatabase(to: backupURL)
        
        // Import on clean Device B with empty local directories
        let dbB = CotLocalDatabase(customURL: rootB.appending(path: "cot.sqlite3"))
        try dbB.importDatabase(from: backupURL)
        
        let mediaB = UserMediaLibraryStore(database: dbB, storageDirectory: rootB.appending(path: "MediaLibrary", directoryHint: .isDirectory))
        let stickersB = CotStickerLibraryStore(database: dbB, stickersDirectory: rootB.appending(path: "MediaLibrary/stickers", directoryHint: .isDirectory))
        let wallpapersB = WallpaperManager(database: dbB, storageDirectory: rootB.appending(path: "Wallpapers", directoryHint: .isDirectory))
        let iconB = AppIconManager(database: dbB, storageDirectory: rootB.appending(path: "CustomAppIcon", directoryHint: .isDirectory))
        let heroB = DashboardHeroCoverStore(database: dbB)
        let inlineDirB = rootB.appending(path: "InlineImages", directoryHint: .isDirectory)
        mediaB.reloadFromDatabase(overwriteMismatchedBlobs: true)
        stickersB.reloadFromDatabase(overwriteMismatchedBlobs: true)
        wallpapersB.reloadFromDatabase(overwriteMismatchedBlobs: true)
        iconB.reloadFromDatabase(overwriteMismatchedBlobs: true)
        dbB.restoreInlineImagesFromDatabase(globalFolder: inlineDirB, overwriteMismatched: true)
        heroB.reloadFromDatabase()
        
        // Verify Media Library (avatars, originals, backgrounds, board assignments)
        #expect(mediaB.avatars.count == 1)
        #expect(mediaB.backgrounds.count == 1)
        let migratedAv = try #require(mediaB.avatars.first)
        let migratedBg = try #require(mediaB.backgrounds.first)
        #expect(migratedAv.title == "裁切头像")
        #expect(migratedAv.editSpec == editedAv.editSpec)
        #expect(migratedAv.originalFilename == editedAv.originalFilename)
        #expect(FileManager.default.fileExists(atPath: mediaB.fileURL(for: migratedAv).path))
        #expect(FileManager.default.fileExists(atPath: mediaB.originalFileURL(for: migratedAv).path))
        #expect(FileManager.default.fileExists(atPath: mediaB.fileURL(for: migratedBg).path))
        #expect(mediaB.thumbnailImage(for: migratedAv) != nil)
        #expect(mediaB.fullImage(for: migratedAv) != nil)
        #expect(mediaB.originalImage(for: migratedAv) != nil)
        #expect(mediaB.boardAssignment(for: .market)?.assetID == bgAsset.id)
        #expect(mediaB.boardBackgroundImage(for: .market) != nil)
        
        // Verify Stickers
        #expect(stickersB.stickers.count == 1)
        let migratedStk = try #require(stickersB.stickers.first)
        #expect(migratedStk.id == stk.id)
        #expect(migratedStk.meaning == "摸鱼猫猫")
        #expect(migratedStk.isFavorite == true)
        #expect(migratedStk.useCount == 1)
        #expect(FileManager.default.fileExists(atPath: stickersB.fileURL(for: migratedStk).path))
        #expect(stickersB.imageData(for: migratedStk.id)?.data == stickerBytesA)
        
        // Verify Wallpapers & authentic pixels (not procedural fallback)
        #expect(wallpapersB.customRecords.count == 2)
        #expect(wallpapersB.spec.selectedID == standaloneWp.id)
        #expect(wallpapersB.spec.isEnabled == true)
        let wpArtwork = wallpapersB.artworkImage(for: standaloneWp.id)
        let cg = try #require(wpArtwork.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let rep = NSBitmapImageRep(cgImage: cg)
        let pixel = try #require(rep.colorAt(x: cg.width / 2, y: cg.height / 2)?.usingColorSpace(.sRGB))
        #expect(pixel.redComponent > 0.65)
        #expect(pixel.blueComponent < 0.35)
        
        // Verify App Icon & Dashboard Hero Cover
        #expect(iconB.hasCustomImage)
        #expect(iconB.spec.source == .customImage)
        #expect(FileManager.default.fileExists(atPath: rootB.appending(path: "CustomAppIcon/user-icon.png").path))
        #expect(heroB.coverImage != nil)
        #expect(abs(heroB.focalX - 0.25) < 0.02)
        #expect(abs(heroB.focalY - 0.72) < 0.02)
        #expect(heroB.fitMode == .fit)
        #expect(heroB.blurStyle == .frosted)
        
        // Verify untitled inline image + transforms
        #expect(FileManager.default.fileExists(atPath: inlineDirB.appending(path: inlineName).path))
        #expect(FileManager.default.fileExists(atPath: inlineDirB.appending(path: "image-transforms.json").path))
    }
    
    
    @Test func legacyDiskOnlyAssetsBackfillAndMigrateCleanly() async throws {
        let rootA = Self.makeTempDir("legacyA")
        let rootB = Self.makeTempDir("legacyB")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        
        let dbA = CotLocalDatabase(customURL: rootA.appending(path: "legacy.sqlite3"))
        let mediaA = UserMediaLibraryStore(database: dbA, storageDirectory: rootA.appending(path: "MediaLibrary", directoryHint: .isDirectory))
        let stickersA = CotStickerLibraryStore(database: dbA, stickersDirectory: rootA.appending(path: "MediaLibrary/stickers", directoryHint: .isDirectory))
        let wallpapersA = WallpaperManager(database: dbA, storageDirectory: rootA.appending(path: "Wallpapers", directoryHint: .isDirectory))
        let iconA = AppIconManager(database: dbA, storageDirectory: rootA.appending(path: "CustomAppIcon", directoryHint: .isDirectory))
        
        let imgFile = rootA.appending(path: "legacy.png")
        try Self.writeSolidPNG(to: imgFile, size: NSSize(width: 80, height: 80), color: .systemGreen)
        _ = mediaA.addImage(from: imgFile, kind: .avatar)
        _ = mediaA.addImage(from: imgFile, kind: .background)
        _ = await stickersA.importFiles([imgFile], defaultCategory: "reaction")
        _ = wallpapersA.saveCustomWallpaper(from: imgFile, title: "旧壁纸")
        if let nsImg = NSImage(contentsOf: imgFile) {
            _ = iconA.saveCustomImage(nsImg)
        }
        
        // Simulate pre-upgrade installation where media_blobs was empty
        dbA.executeSQL("DELETE FROM media_blobs;")
        #expect(dbA.fetchMediaBlobMetadata(in: .mediaAvatar).isEmpty)
        #expect(dbA.fetchMediaBlobMetadata(in: .sticker).isEmpty)
        
        mediaA.syncBlobsToDatabase()
        stickersA.syncBlobsToDatabase()
        wallpapersA.syncBlobsToDatabase()
        iconA.syncBlobsToDatabase()
        
        let backupURL = rootA.appending(path: "backfilled.sqlite3")
        try dbA.exportDatabase(to: backupURL)
        
        let dbB = CotLocalDatabase(customURL: rootB.appending(path: "restored.sqlite3"))
        try dbB.importDatabase(from: backupURL)
        let mediaB = UserMediaLibraryStore(database: dbB, storageDirectory: rootB.appending(path: "MediaLibrary", directoryHint: .isDirectory))
        let stickersB = CotStickerLibraryStore(database: dbB, stickersDirectory: rootB.appending(path: "MediaLibrary/stickers", directoryHint: .isDirectory))
        let wallpapersB = WallpaperManager(database: dbB, storageDirectory: rootB.appending(path: "Wallpapers", directoryHint: .isDirectory))
        let iconB = AppIconManager(database: dbB, storageDirectory: rootB.appending(path: "CustomAppIcon", directoryHint: .isDirectory))
        
        #expect(mediaB.avatars.count == 1)
        #expect(mediaB.backgrounds.count == 1)
        #expect(mediaB.thumbnailImage(for: try #require(mediaB.avatars.first)) != nil)
        #expect(mediaB.fullImage(for: try #require(mediaB.backgrounds.first)) != nil)
        #expect(stickersB.stickers.count == 1)
        #expect(wallpapersB.customRecords.count == 1)
        #expect(iconB.hasCustomImage)
    }
    
    
    @Test func editedAssetOverwritesStaleDiskFileOnReimport() throws {
        let rootA = Self.makeTempDir("editA")
        let rootB = Self.makeTempDir("editB")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        
        let dbA = CotLocalDatabase(customURL: rootA.appending(path: "a.sqlite3"))
        let mediaA = UserMediaLibraryStore(database: dbA, storageDirectory: rootA.appending(path: "MediaLibrary", directoryHint: .isDirectory))
        let imgFile = rootA.appending(path: "av.png")
        try Self.writeSolidPNG(to: imgFile, size: NSSize(width: 128, height: 128), color: .systemPurple)
        let av = try #require(mediaA.addImage(from: imgFile, kind: .avatar).asset)
        
        let firstBackup = rootA.appending(path: "v1.sqlite3")
        try dbA.exportDatabase(to: firstBackup)
        
        let dbB = CotLocalDatabase(customURL: rootB.appending(path: "b.sqlite3"))
        try dbB.importDatabase(from: firstBackup)
        let mediaB = UserMediaLibraryStore(database: dbB, storageDirectory: rootB.appending(path: "MediaLibrary", directoryHint: .isDirectory))
        let v1BytesOnB = try Data(contentsOf: mediaB.fileURL(for: try #require(mediaB.avatars.first)))
        
        // Now Device A crops & zooms the avatar and exports v2
        _ = try #require(mediaA.updateAssetEdit(
            id: av.id,
            kind: .avatar,
            editSpec: UserMediaEditSpec(scale: 2.1, panX: 0.35, panY: -0.25, aspectPreset: .square, quarterTurns: 1, flipHorizontal: false)
        ))
        let v2BytesOnA = try Data(contentsOf: mediaA.fileURL(for: av))
        #expect(v2BytesOnA != v1BytesOnB)
        
        let secondBackup = rootA.appending(path: "v2.sqlite3")
        try dbA.exportDatabase(to: secondBackup)
        
        try dbB.importDatabase(from: secondBackup)
        mediaB.reloadFromDatabase(overwriteMismatchedBlobs: true)
        
        let v2BytesOnB = try Data(contentsOf: mediaB.fileURL(for: try #require(mediaB.avatars.first)))
        #expect(v2BytesOnB == v2BytesOnA)
        #expect(FileManager.default.fileExists(atPath: mediaB.originalFileURL(for: try #require(mediaB.avatars.first)).path))
    }
    
    
    @Test func deletingAssetsPrunesMediaBlobs() async throws {
        let root = Self.makeTempDir("prune")
        defer { try? FileManager.default.removeItem(at: root) }
        
        let db = CotLocalDatabase(customURL: root.appending(path: "prune.sqlite3"))
        let media = UserMediaLibraryStore(database: db, storageDirectory: root.appending(path: "MediaLibrary", directoryHint: .isDirectory))
        let stickers = CotStickerLibraryStore(database: db, stickersDirectory: root.appending(path: "MediaLibrary/stickers", directoryHint: .isDirectory))
        let wallpapers = WallpaperManager(database: db, storageDirectory: root.appending(path: "Wallpapers", directoryHint: .isDirectory))
        
        let file = root.appending(path: "asset.png")
        try Self.writeSolidPNG(to: file, size: NSSize(width: 90, height: 90), color: .systemYellow)
        
        let av = try #require(media.addImage(from: file, kind: .avatar).asset)
        _ = media.updateAssetEdit(id: av.id, kind: .avatar, editSpec: UserMediaEditSpec(scale: 1.5))
        let bg = try #require(media.addImage(from: file, kind: .background).asset)
        _ = await stickers.importFiles([file], defaultCategory: "custom")
        let stk = try #require(stickers.stickers.first)
        let wp = try #require(wallpapers.saveCustomWallpaper(from: file, title: "temp"))
        
        #expect(db.fetchMediaBlobMetadata(in: .mediaAvatar).count == 2)
        #expect(db.fetchMediaBlobMetadata(in: .mediaBackground).count == 1)
        #expect(db.fetchMediaBlobMetadata(in: .sticker).count == 1)
        #expect(db.fetchMediaBlobMetadata(in: .wallpaper).count == 1)
        
        media.deleteAsset(id: av.id, kind: .avatar)
        media.deleteAsset(id: bg.id, kind: .background)
        stickers.deleteSticker(id: stk.id)
        wallpapers.deleteCustomWallpaper(id: wp.id)
        
        #expect(db.fetchMediaBlobMetadata(in: .mediaAvatar).isEmpty)
        #expect(db.fetchMediaBlobMetadata(in: .mediaBackground).isEmpty)
        #expect(db.fetchMediaBlobMetadata(in: .sticker).isEmpty)
        #expect(db.fetchMediaBlobMetadata(in: .wallpaper).isEmpty)
    }
    
    
    @Test func mediaBlobPathSanitizerRejectsTraversalAndInvalidPaths() {
        let root = FileManager.default.temporaryDirectory.appending(path: "sanitizer_root", directoryHint: .isDirectory)
        #expect(MediaBlobPathSanitizer.sanitizeRelativePath("../a.png") == nil)
        #expect(MediaBlobPathSanitizer.sanitizeRelativePath("/abs/a.png") == nil)
        #expect(MediaBlobPathSanitizer.sanitizeRelativePath("a/../b.png") == nil)
        #expect(MediaBlobPathSanitizer.sanitizeRelativePath("a\\b.png") == nil)
        #expect(MediaBlobPathSanitizer.sanitizeRelativePath("") == nil)
        #expect(MediaBlobPathSanitizer.sanitizeRelativePath("a\0b.png") == nil)
        #expect(MediaBlobPathSanitizer.safeDestinationURL(rootDirectory: root, relativePath: "../escape.png") == nil)
        
        #expect(MediaBlobPathSanitizer.sanitizeRelativePath("av-1.png") == "av-1.png")
        #expect(MediaBlobPathSanitizer.sanitizeRelativePath("originals/av-1.png") == "originals/av-1.png")
        #expect(MediaBlobPathSanitizer.sanitizeRelativePath("cat/stk_1.gif") == "cat/stk_1.gif")
        #expect(MediaBlobPathSanitizer.safeDestinationURL(rootDirectory: root, relativePath: "cat/stk_1.gif") != nil)
    }
    
    
    // MARK: - Helpers
    
    private static func makeTempDir(_ label: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "cot_media_mig_\(label)_\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    
    private static func writeSolidPNG(to url: URL, size: NSSize, color: NSColor) throws {
        let data = try Self.encodeSolidImage(size: size, color: color, type: .png, properties: [:])
        try data.write(to: url)
    }
    
    
    private static func writeSolidJPEG(to url: URL, size: NSSize, color: NSColor) throws {
        let data = try Self.encodeSolidImage(size: size, color: color, type: .jpeg, properties: [.compressionFactor: 0.88])
        try data.write(to: url)
    }
    
    
    private static func encodeSolidImage(
        size: NSSize,
        color: NSColor,
        type: NSBitmapImageRep.FileType,
        properties: [NSBitmapImageRep.PropertyKey: Any]
    ) throws -> Data {
        let w = Int(size.width)
        let h = Int(size.height)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w,
            pixelsHigh: h,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try #require(rep.representation(using: type, properties: properties))
    }
}
