//
//  StickerLibraryAndEmotionTests.swift
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
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct StickerLibraryAndEmotionTests {
    
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "coteditor-sticker-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    
    private func makeTestPNG(color: NSColor, width: Int = 64, height: Int = 64) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
    
    
    @Test func stickerImportDeduplicationAndSearch() async throws {
        let tempDir = self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "test.sqlite3"))
        let store = CotStickerLibraryStore(database: db, stickersDirectory: tempDir.appending(path: "stickers", directoryHint: .isDirectory))
        
        let img1URL = tempDir.appending(path: "cat_happy.png")
        let img2URL = tempDir.appending(path: "cat_dup.png")
        let img3URL = tempDir.appending(path: "dog_speechless.png")
        let pngA = self.makeTestPNG(color: .systemOrange)
        let pngB = self.makeTestPNG(color: .systemBlue)
        try pngA.write(to: img1URL)
        try pngA.write(to: img2URL)
        try pngB.write(to: img3URL)
        
        let result = await store.importFiles([img1URL, img2URL, img3URL], defaultCategory: "cat")
        #expect(result.addedCount == 2)
        #expect(result.skippedDuplicates == 1)
        #expect(store.stickers.count == 2)
        
        let first = try #require(store.stickers.first)
        store.updateSemantics(
            id: first.id,
            category: "cat",
            ocrText: "加班写代码",
            meaning: "打工人猫猫无奈加班",
            moods: ["无语", "摸鱼"],
            tags: ["加班", "代码"]
        )
        store.toggleFavorite(id: first.id)
        
        let matches = store.search(query: "加班", mood: "无语", limit: 5)
        #expect(matches.first?.id == first.id)
        #expect(matches.first?.isFavorite == true)
    }
    
    
    @Test func botEmotionStateEvolutionAndDecay() {
        let base = BotEmotionEngine.initialState(botID: "custom_1", baseline: .warm, now: Date(timeIntervalSince1970: 1_000_000))
        #expect(base.mood == .happy)
        
        let praised = BotEmotionEngine.evolve(base, userPrompt: "干得漂亮太棒了", botReply: "哈哈", explicitMoodTag: nil, now: Date(timeIntervalSince1970: 1_000_100))
        #expect(praised.mood == .happy || praised.mood == .excited)
        #expect(praised.energy >= base.energy)
        
        let complained = BotEmotionEngine.evolve(praised, userPrompt: "又报错返工了", botReply: "", explicitMoodTag: nil, now: Date(timeIntervalSince1970: 1_000_200))
        #expect(complained.mood == .aggrieved)
        
        let decayed = BotEmotionEngine.decayed(complained, now: Date(timeIntervalSince1970: 1_000_200 + 9 * 3600))
        #expect(decayed.mood == .happy)
    }
    
    
    @Test func stickerDirectiveThreeLayerGate() {
        let allowed = Set(["stk_1", "stk_2"])
        
        // Allowed sticker-only in casual chat when below turn cap
        let casual = BotReplyDirectiveParser.parse(
            raw: "[STICKER:stk_1] [MOOD:speechless]",
            allowedStickerIDs: allowed,
            allowStickerOnly: true,
            stickerOnlyCountInTurn: 0
        )
        #expect(casual.stickerID == "stk_1")
        #expect(casual.mood == .speechless)
        #expect(casual.isStickerOnly == true)
        
        // Capped at maxStickerOnlyPerTurn = 2 -> ensures text is never empty
        let capped = BotReplyDirectiveParser.parse(
            raw: "[STICKER:stk_1]",
            allowedStickerIDs: allowed,
            allowStickerOnly: true,
            stickerOnlyCountInTurn: 2
        )
        #expect(capped.stickerID == "stk_1")
        #expect(!capped.text.isEmpty)
        
        // Unknown hallucinated sticker ID is stripped
        let unknown = BotReplyDirectiveParser.parse(
            raw: "好主意 [STICKER:fake_999]",
            allowedStickerIDs: allowed,
            allowStickerOnly: false,
            stickerOnlyCountInTurn: 0
        )
        #expect(unknown.stickerID == nil)
        #expect(unknown.text == "好主意")
    }
    
    
    @Test func customBotCRUDAndMultiSessionMeetingRoom() {
        let tempDir = self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "meeting.sqlite3"))
        
        let botStore = AIBotStore(database: db)
        let custom = botStore.createCustomBot(
            name: "架构毒舌",
            nickname: "毒舌",
            personaPrompt: "犀利指出方案隐患",
            baseline: .sharpTongued,
            preferredStickerCategories: ["baoman", "cat"]
        )
        #expect(botStore.customBots.count == 1)
        #expect(botStore.unifiedBot(id: custom.id)?.name == "架构毒舌")
        
        let manager = ButlerMeetingRoomManager(database: db)
        let firstID = manager.activeSessionID
        #expect(!firstID.isEmpty)
        
        let second = manager.createSession(title: "AIME 评审", botStore: botStore)
        #expect(manager.sessions.count == 2)
        #expect(manager.activeSessionID == second.id)
        
        manager.renameSession(second.id, title: "AIME 数据链路评审")
        #expect(manager.activeSession?.title == "AIME 数据链路评审")
        
        manager.togglePinSession(second.id)
        #expect(manager.activeSession?.isPinned == true)
        
        let beforeCount = manager.activeParticipantIDs.count
        if let firstBot = manager.activeParticipantIDs.first(where: { $0 != "butler" }) {
            manager.toggleParticipant(firstBot)
            #expect(manager.activeParticipantIDs.count == beforeCount - 1)
        }
        
        manager.deleteSession(second.id)
        #expect(manager.sessions.count == 1)
        #expect(manager.activeSessionID == firstID)
        
        botStore.deleteCustomBot(id: custom.id)
        #expect(botStore.customBots.isEmpty)
    }
    
    
    @Test func squareAvatarFullBleedAndStickerDeletionSync() async throws {
        // 1. Verify squareAvatar renders full-bleed into all 4 quadrants (regression against 1/4-corner crop bug)
        let pngData = self.makeTestPNG(color: .systemRed, width: 120, height: 180)
        let sourceImage = try #require(NSImage(data: pngData))
        let rendered = try #require(
            AIGijinkaImageLoader.renderSquareAvatarBitmap(from: sourceImage, cropAnchor: .top, pointSize: 48)
        )
        let cg = try #require(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let rep = NSBitmapImageRep(cgImage: cg)
        let topRight = try #require(rep.colorAt(x: cg.width - 6, y: 6)?.usingColorSpace(.sRGB))
        let bottomLeft = try #require(rep.colorAt(x: 6, y: cg.height - 6)?.usingColorSpace(.sRGB))
        // Red source must dominate over green/blue in top-right as well as bottom-left (not white!)
        #expect(topRight.redComponent > 0.6)
        #expect(topRight.greenComponent < 0.45)
        #expect(bottomLeft.redComponent > 0.6)
        
        // 2. Verify sticker deletion and disk/DB orphan pruning stay in sync
        let tempDir = self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "sync.sqlite3"))
        let store = CotStickerLibraryStore(database: db, stickersDirectory: tempDir.appending(path: "stickers", directoryHint: .isDirectory))
        
        let img1URL = tempDir.appending(path: "one.png")
        let img2URL = tempDir.appending(path: "two.png")
        try self.makeTestPNG(color: .systemGreen).write(to: img1URL)
        try self.makeTestPNG(color: .systemPurple).write(to: img2URL)
        _ = await store.importFiles([img1URL, img2URL], defaultCategory: "custom")
        #expect(store.stickers.count == 2)
        
        let deletedID = store.stickers[0].id
        store.deleteSticker(id: deletedID)
        #expect(store.stickers.count == 1)
        #expect(store.sticker(id: deletedID) == nil)
        #expect(store.imageData(for: deletedID) == nil)
        #expect(db.fetchAllStickers().count == 1)
        
        // Simulate external file deletion on disk -> syncWithDiskAndDatabase prunes orphaned DB row
        let remaining = try #require(store.stickers.first)
        try FileManager.default.removeItem(at: store.fileURL(for: remaining))
        store.syncWithDiskAndDatabase()
        #expect(store.stickers.isEmpty)
        #expect(db.fetchAllStickers().isEmpty)
    }
}
