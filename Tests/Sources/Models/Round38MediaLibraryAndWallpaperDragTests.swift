//
//  Round38MediaLibraryAndWallpaperDragTests.swift
//
//  Tests
//  https://coteditor.com
//

import AppKit
import Foundation
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round38MediaLibraryAndWallpaperDragTests {
    
    @Test func settingsMediaLibraryTabMetadataIsValid() {
        #expect(SidebarSettingsItem.allCases.contains(.mediaLibrary))
        let item = SidebarSettingsItem.mediaLibrary
        #expect(!item.title.isEmpty)
        #expect(!item.title.contains("与"))
        #expect(NSImage(systemSymbolName: item.symbolName, accessibilityDescription: nil) != nil)
        
        if let wallpaperIdx = SidebarSettingsItem.allCases.firstIndex(of: .wallpaper),
           let libraryIdx = SidebarSettingsItem.allCases.firstIndex(of: .mediaLibrary)
        {
            #expect(libraryIdx == wallpaperIdx + 1)
        }
    }
    
    
    @Test func mediaLibrarySmartFolderImportDeduplicatesPersistsAndCleansAssignments() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "cot_r38_media_\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        
        let imgsRoot = tempRoot.appending(path: "imgs", directoryHint: .isDirectory)
        let avatarsDir = imgsRoot.appending(path: "avatars", directoryHint: .isDirectory)
        let bgsDir = imgsRoot.appending(path: "bgs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: avatarsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bgsDir, withIntermediateDirectories: true)
        
        try Self.writeSolidPNG(to: avatarsDir.appending(path: "av1.png"), size: NSSize(width: 96, height: 96), color: .systemPink)
        try Self.writeSolidPNG(to: avatarsDir.appending(path: "av2.png"), size: NSSize(width: 96, height: 96), color: .systemTeal)
        try Self.writeSolidJPEG(to: bgsDir.appending(path: "bg1.jpg"), size: NSSize(width: 320, height: 200), color: .systemIndigo)
        try Self.writeSolidJPEG(to: bgsDir.appending(path: "bg2.jpg"), size: NSSize(width: 320, height: 200), color: .systemOrange)
        // Hidden metadata file must be ignored cleanly
        try Data([0x00, 0x01]).write(to: imgsRoot.appending(path: ".DS_Store"))
        
        let db = CotLocalDatabase(customURL: tempRoot.appending(path: "media.sqlite3"))
        let libraryDir = tempRoot.appending(path: "MediaLibrary", directoryHint: .isDirectory)
        let store = UserMediaLibraryStore(database: db, storageDirectory: libraryDir)
        
        let firstImport = store.importURLs([imgsRoot], preferredKind: .avatar)
        #expect(firstImport.avatarsAdded == 2)
        #expect(firstImport.backgroundsAdded == 2)
        #expect(firstImport.skippedDuplicates == 0)
        #expect(firstImport.failedCount == 0)
        #expect(store.avatars.count == 2)
        #expect(store.backgrounds.count == 2)
        
        // Re-importing the exact same folder skips duplicates by SHA256
        let duplicateImport = store.importURLs([imgsRoot], preferredKind: .background)
        #expect(duplicateImport.avatarsAdded == 0)
        #expect(duplicateImport.backgroundsAdded == 0)
        #expect(duplicateImport.skippedDuplicates == 4)
        
        let bgAsset = try #require(store.backgrounds.first)
        store.setBoardBackground(assetID: bgAsset.id, for: .market, opacity: 0.99, blurRadius: 80)
        let assignment = try #require(store.boardAssignment(for: .market))
        #expect(assignment.opacity <= 0.55)
        #expect(assignment.blurRadius <= 28.0)
        #expect(store.boardBackgroundImage(for: .market) != nil)
        
        // Reload from SQLite
        let reloaded = UserMediaLibraryStore(database: db, storageDirectory: libraryDir)
        #expect(reloaded.avatars.count == 2)
        #expect(reloaded.backgrounds.count == 2)
        #expect(reloaded.boardAssignment(for: .market)?.assetID == bgAsset.id)
        #expect(reloaded.thumbnailImage(for: try #require(reloaded.avatars.first)) != nil)
        #expect(reloaded.fullImage(for: bgAsset) != nil)
        
        // Deleting assigned background cleans board assignment & disk file
        let bgFileURL = reloaded.fileURL(for: bgAsset)
        #expect(FileManager.default.fileExists(atPath: bgFileURL.path))
        reloaded.deleteAsset(id: bgAsset.id, kind: .background)
        #expect(!reloaded.backgrounds.contains(where: { $0.id == bgAsset.id }))
        #expect(reloaded.boardAssignment(for: .market) == nil)
        #expect(!FileManager.default.fileExists(atPath: bgFileURL.path))
    }
    
    
    @Test func mediaLibraryAssignmentsTargetBotsWallpaperHeroAndAllBoards() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "cot_r38_assign_\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        
        let avURL = tempRoot.appending(path: "bot_avatar.png")
        let bgURL = tempRoot.appending(path: "board_bg.jpg")
        try Self.writeSolidPNG(to: avURL, size: NSSize(width: 128, height: 128), color: .systemPurple)
        try Self.writeSolidJPEG(to: bgURL, size: NSSize(width: 480, height: 300), color: .systemBlue)
        
        let db = CotLocalDatabase(customURL: tempRoot.appending(path: "assign.sqlite3"))
        let store = UserMediaLibraryStore(database: db, storageDirectory: tempRoot.appending(path: "lib", directoryHint: .isDirectory))
        let botStore = AIBotStore(database: db)
        let wallpaperManager = WallpaperManager(database: db, storageDirectory: tempRoot.appending(path: "wallpapers", directoryHint: .isDirectory))
        let heroStore = DashboardHeroCoverStore(database: db)
        
        let av = try #require(store.addImage(from: avURL, kind: .avatar).asset)
        let bg = try #require(store.addImage(from: bgURL, kind: .background).asset)
        
        // 1. Bot avatar assignment
        #expect(store.applyAvatar(assetID: av.id, to: .summarize, botStore: botStore))
        #expect(botStore.customAvatarImage(for: .summarize) != nil)
        
        // 2. Editor wallpaper assignment (idempotent without duplicating records)
        #expect(store.applyBackgroundToEditorWallpaper(assetID: bg.id, wallpaperManager: wallpaperManager))
        #expect(wallpaperManager.spec.isEnabled)
        #expect(wallpaperManager.spec.selectedID == WallpaperManager.mediaLibraryWallpaperID(for: bg.id))
        #expect(wallpaperManager.customRecords.count == 1)
        #expect(store.applyBackgroundToEditorWallpaper(assetID: bg.id, wallpaperManager: wallpaperManager))
        #expect(wallpaperManager.customRecords.count == 1)
        
        // 3. Dashboard Hero cover assignment
        #expect(store.applyBackgroundToDashboardHero(assetID: bg.id, heroStore: heroStore))
        #expect(heroStore.coverImage != nil)
        
        // 4. All pane board slots (market, podcast, news, butler)
        for kind in PaneBoardKind.allCases {
            let slot = BoardBackgroundSlot(paneBoardKind: kind)
            store.setBoardBackground(assetID: bg.id, for: slot, opacity: 0.32, blurRadius: 12)
            #expect(store.boardAssignment(for: slot)?.assetID == bg.id)
            store.updateBoardBackgroundStyle(for: slot, opacity: 0.40, blurRadius: 6)
            #expect(abs((store.boardAssignment(for: slot)?.opacity ?? 0) - 0.40) < 0.001)
            #expect(abs((store.boardAssignment(for: slot)?.blurRadius ?? 0) - 6.0) < 0.001)
        }
    }
    
    
    @Test func wallpaperInteractionViewOptOutOfWindowBackgroundDraggingAndFramingMath() {
        let interactionView = WallpaperFramingInteractionNSView(frame: NSRect(x: 0, y: 0, width: 320, height: 158))
        #expect(interactionView.mouseDownCanMoveWindow == false)
        #expect(interactionView.isFlipped == true)
        #expect(interactionView.acceptsFirstMouse(for: nil) == true)
        
        // Wide image in a landscape preview has horizontal slack even at 1.0x
        let wideResult = WallpaperManager.dragUpdatedFraming(
            start: WallpaperFraming(scale: 1.0, panX: 0.0, panY: 0.0),
            imageSize: CGSize(width: 1920, height: 1080),
            viewportSize: CGSize(width: 300, height: 240),
            translation: CGSize(width: -40, height: 0)
        )
        #expect(wideResult.panX > 0.0)
        #expect((-1.0...1.0).contains(wideResult.panX))
        
        // Aspect-matched image at 1.0x smoothly nudges scale so dragging always frames freely
        let matchedResult = WallpaperManager.dragUpdatedFraming(
            start: WallpaperFraming(scale: 1.0, panX: 0.0, panY: 0.0),
            imageSize: CGSize(width: 1000, height: 500),
            viewportSize: CGSize(width: 320, height: 160),
            translation: CGSize(width: 24, height: -18)
        )
        #expect(matchedResult.scale >= 1.22)
        #expect(matchedResult.panX < 0.0)
        #expect(matchedResult.panY > 0.0)
        
        // Huge drag translation clamps safely to [-1, 1]
        let clampedResult = WallpaperManager.dragUpdatedFraming(
            start: WallpaperFraming(scale: 1.5, panX: 0.5, panY: 0.5),
            imageSize: CGSize(width: 1200, height: 800),
            viewportSize: CGSize(width: 300, height: 160),
            translation: CGSize(width: -5000, height: -5000)
        )
        #expect(clampedResult.panX == 1.0)
        #expect(clampedResult.panY == 1.0)
    }
    
    
    // MARK: - Test Image Helpers
    
    private static func writeSolidPNG(to url: URL, size: NSSize, color: NSColor) throws {
        let data = try Self.encodeSolidImage(size: size, color: color, type: .png, properties: [:])
        try data.write(to: url)
    }
    
    private static func writeSolidJPEG(to url: URL, size: NSSize, color: NSColor) throws {
        let data = try Self.encodeSolidImage(size: size, color: color, type: .jpeg, properties: [.compressionFactor: 0.85])
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
        NSRect(origin: .zero, size: size).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try #require(rep.representation(using: type, properties: properties))
    }
}
