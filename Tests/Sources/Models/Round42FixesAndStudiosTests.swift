//
//  Round42FixesAndStudiosTests.swift
//
//  Tests
//  https://coteditor.com
//

import AppKit
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round42FixesAndStudiosTests {
    
    // MARK: 1. Data Funnel (Junk/Garbled Deletion + Duplicate Merging + Sharded Batching)
    
    @Test func dataFunnelFiltersJunkMergesDuplicatesAndShardsCleanly() async {
        let now = Date()
        let inputs: [OrganizeFunnelInput] = [
            // Meaningful real documents (must survive)
            OrganizeFunnelInput(
                id: "doc:arch-1",
                dbRecordID: "doc:arch-1",
                title: "核心架构演进方案",
                filePath: nil,
                syntax: "Markdown",
                currentGroup: "",
                content: "# 核心架构演进方案\n\n第一阶段完成数据漏斗清洗与并行分片归类，降低整理耗时。\n\n第二阶段优化本地缓存与星图渲染帧率。",
                updatedAt: now,
                isOpenNow: true,
                isUntitled: false
            ),
            // Duplicate copy of arch-1 with extra paragraph (must merge losslessly into arch-1)
            OrganizeFunnelInput(
                id: "doc:arch-2",
                dbRecordID: "doc:arch-2",
                title: "核心架构演进方案 副本",
                filePath: nil,
                syntax: "Markdown",
                currentGroup: "项目方案",
                content: "# 核心架构演进方案\n\n第一阶段完成数据漏斗清洗与并行分片归类，降低整理耗时。\n\n补充：支持一键撤销恢复合并前内容。",
                updatedAt: now.addingTimeInterval(-300),
                isOpenNow: false,
                isUntitled: false
            ),
            // Exact duplicate of meeting note
            OrganizeFunnelInput(
                id: "doc:meet-1",
                dbRecordID: "doc:meet-1",
                title: "周三评审会议纪要",
                filePath: nil,
                syntax: "Markdown",
                currentGroup: "",
                content: "周三产品评审会议纪要：确认壁纸比例采用窗口真实纵横比，素材库支持裁切缩放。",
                updatedAt: now,
                isOpenNow: false,
                isUntitled: false
            ),
            OrganizeFunnelInput(
                id: "doc:meet-2",
                dbRecordID: "doc:meet-2",
                title: "未命名 2",
                filePath: nil,
                syntax: "Plain Text",
                currentGroup: "",
                content: "周三产品评审会议纪要：确认壁纸比例采用窗口真实纵横比，素材库支持裁切缩放。",
                updatedAt: now.addingTimeInterval(-60),
                isOpenNow: false,
                isUntitled: true
            ),
            // Meaningless test / empty / keyboard smash / garbled docs (must be deleted by Stage 1)
            OrganizeFunnelInput(
                id: "doc:junk-empty",
                dbRecordID: "doc:junk-empty",
                title: "未命名 3",
                filePath: nil,
                syntax: "Plain Text",
                currentGroup: "",
                content: "   \n#   \n---",
                updatedAt: now,
                isOpenNow: false,
                isUntitled: true
            ),
            OrganizeFunnelInput(
                id: "doc:junk-test",
                dbRecordID: "doc:junk-test",
                title: "test1",
                filePath: nil,
                syntax: "Plain Text",
                currentGroup: "",
                content: "测试一下",
                updatedAt: now,
                isOpenNow: false,
                isUntitled: true
            ),
            OrganizeFunnelInput(
                id: "doc:junk-smash",
                dbRecordID: "doc:junk-smash",
                title: "未命名 4",
                filePath: nil,
                syntax: "Plain Text",
                currentGroup: "",
                content: "asdfghjklasdfgh",
                updatedAt: now,
                isOpenNow: false,
                isUntitled: true
            ),
            OrganizeFunnelInput(
                id: "doc:junk-garbled",
                dbRecordID: "doc:junk-garbled",
                title: "乱码",
                filePath: nil,
                syntax: "Plain Text",
                currentGroup: "",
                content: "锟斤拷锟斤拷锟斤拷\u{FFFD}\u{FFFD}\u{FFFD}Ã©Ã¤Ã¶",
                updatedAt: now,
                isOpenNow: false,
                isUntitled: true
            ),
        ]
        
        let plan = await DocumentOrganizeFunnel.runFullPipeline(
            items: inputs,
            existingGroups: ["项目方案"],
            allowRemoteAI: false,
            shardSize: 2
        )
        
        let junkIDs = Set(plan.funnel.junkToDelete.map(\.item.id))
        #expect(junkIDs == Set(["doc:junk-empty", "doc:junk-test", "doc:junk-smash", "doc:junk-garbled"]))
        
        #expect(plan.funnel.mergeClusters.count == 2)
        #expect(plan.funnel.deletedDuplicateCount == 2)
        #expect(plan.funnel.survivors.count == 2)
        
        let mergedArch = plan.funnel.mergeClusters.first(where: { $0.primary.id == "doc:arch-1" })
        #expect(mergedArch != nil)
        #expect(mergedArch?.mergedContent.contains("第二阶段优化本地缓存") == true)
        #expect(mergedArch?.mergedContent.contains("补充：支持一键撤销恢复合并前内容") == true)
        #expect(mergedArch?.bestGroup == "项目方案")
        
        let shards = DocumentOrganizeFunnel.makeShards(Array(0..<35), shardSize: 14)
        #expect(shards.count == 3)
        #expect(shards.map(\.count) == [14, 14, 7])
        
        let consolidated = DocumentOrganizeFunnel.consolidateAssignments(
            [
                .init(id: "1", group: "编程开发", suggestedTitle: nil),
                .init(id: "2", group: "会议记录", suggestedTitle: nil),
                .init(id: "3", group: "自定义组", suggestedTitle: nil),
            ],
            existingGroups: ["自定义组"]
        )
        #expect(consolidated.map(\.group) == ["代码开发", "会议纪要", "自定义组"])
    }
    
    
    // MARK: 2. Document Save & Quit-Prompt Bug Fix
    
    @Test func quickSaveClearsDirtyAndDraftStateForUntitledAndFileBackedDocuments() async throws {
        // 1. Untitled SQLite-backed document: edit -> needs prompt; ⌘S -> clean & canClose == true
        let untitled = Document()
        untitled.displayName = "测试保存无弹窗"
        untitled.textStorage.replaceCharacters(
            in: NSRange(location: 0, length: untitled.textStorage.length),
            with: "已保存的重要笔记内容"
        )
        untitled.markEditedByUser()
        untitled.updateChangeCount(.changeDone)
        #expect(untitled.needsUserSavePrompt == true)
        
        untitled.performQuickSave(nil)
        #expect(untitled.hasUncommittedChanges == false)
        #expect(untitled.isDocumentEdited == false)
        #expect(untitled.isDraft == false)
        #expect(untitled.needsUserSavePrompt == false)
        #expect(await untitled.canClose() == true)
        
        // Clean up DB record created by performQuickSave
        let rawDocID = untitled.databaseDocumentID.hasPrefix("doc:") ? untitled.databaseDocumentID : "doc:\(untitled.databaseDocumentID)"
        CotLocalDatabase.shared.permanentlyDeleteDocument(id: rawDocID, filePath: nil)
        untitled.close()
        
        // 2. File-backed document in temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot_r42_save_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let fileURL = tempDir.appending(path: "sample.txt")
        try "initial".write(to: fileURL, atomically: true, encoding: .utf8)
        
        let fileDoc = try Document(contentsOf: fileURL, ofType: UTType.plainText.identifier)
        defer {
            CotLocalDatabase.shared.permanentlyDeleteDocument(id: fileURL.path(percentEncoded: false), filePath: fileURL.path(percentEncoded: false))
            fileDoc.close()
        }
        #expect(fileDoc.needsUserSavePrompt == false)
        
        fileDoc.textStorage.replaceCharacters(
            in: NSRange(location: 0, length: fileDoc.textStorage.length),
            with: "updated after cmd-s"
        )
        fileDoc.markEditedByUser()
        fileDoc.updateChangeCount(.changeDone)
        #expect(fileDoc.needsUserSavePrompt == true)
        
        fileDoc.performQuickSave(nil)
        // Allow async disk write completion to finish
        for _ in 0..<40 where fileDoc.needsUserSavePrompt {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(fileDoc.hasUncommittedChanges == false)
        #expect(fileDoc.isDocumentEdited == false)
        #expect(fileDoc.needsUserSavePrompt == false)
        #expect(await fileDoc.canClose() == true)
        let savedText = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(savedText == "updated after cmd-s")
    }
    
    
    // MARK: 3. Material Library Non-Destructive Crop/Zoom/Pan/Aspect Editor
    
    @Test func mediaLibraryPreservesOriginalAndRendersCroppedAvatarAndBackground() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "cot_r42_media_edit_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        
        let avURL = tempRoot.appending(path: "portrait.png")
        let bgURL = tempRoot.appending(path: "landscape.jpg")
        try Self.writePatternImage(to: avURL, size: NSSize(width: 300, height: 420), type: .png)
        try Self.writePatternImage(to: bgURL, size: NSSize(width: 800, height: 600), type: .jpeg)
        
        let db = CotLocalDatabase(customURL: tempRoot.appending(path: "media_edit.sqlite3"))
        let store = UserMediaLibraryStore(database: db, storageDirectory: tempRoot.appending(path: "lib", directoryHint: .isDirectory))
        let wpManager = WallpaperManager(database: db, storageDirectory: tempRoot.appending(path: "wp", directoryHint: .isDirectory))
        
        let av = try #require(store.addImage(from: avURL, kind: .avatar).asset)
        let bg = try #require(store.addImage(from: bgURL, kind: .background).asset)
        
        // Edit avatar: 1:1 square, zoom 1.8x, pan, rotate 90°, flip
        let avSpec = UserMediaEditSpec(
            scale: 1.8,
            panX: 0.35,
            panY: -0.25,
            aspectPreset: .square,
            quarterTurns: 1,
            flipHorizontal: true
        )
        let editedAv = try #require(store.updateAssetEdit(id: av.id, kind: .avatar, title: "居中头像", editSpec: avSpec, wallpaperManager: wpManager))
        #expect(editedAv.title == "居中头像")
        #expect(editedAv.pixelWidth == editedAv.pixelHeight)
        #expect(editedAv.editSpec == avSpec)
        #expect(editedAv.originalFilename != nil)
        #expect(FileManager.default.fileExists(atPath: store.originalFileURL(for: editedAv).path(percentEncoded: false)))
        
        // Apply background as editor wallpaper, then crop to 16:9 and verify live wallpaper refresh
        #expect(store.applyBackgroundToEditorWallpaper(assetID: bg.id, wallpaperManager: wpManager))
        let bgSpec = UserMediaEditSpec(scale: 1.5, panX: -0.2, panY: 0.4, aspectPreset: .landscape16x9)
        let editedBg = try #require(store.updateAssetEdit(id: bg.id, kind: .background, title: "宽屏背景", editSpec: bgSpec, wallpaperManager: wpManager))
        let ratio = Double(editedBg.pixelWidth) / Double(max(1, editedBg.pixelHeight))
        #expect(abs(ratio - (16.0 / 9.0)) < 0.03)
        #expect(wpManager.spec.selectedID == WallpaperManager.mediaLibraryWallpaperID(for: bg.id))
        
        // Verify editor sheet mounts cleanly
        let sheet = MediaAssetCropEditorSheet(asset: editedAv, library: store, onDismiss: {}, onSaved: { _ in })
        let host = NSHostingView(rootView: sheet)
        host.frame = NSRect(x: 0, y: 0, width: 548, height: 460)
        host.layoutSubtreeIfNeeded()
        #expect(host.bounds.width == 548)
    }
    
    
    // MARK: 4. Apple-Style Wallpaper Display Modes, Generous Ranges & Reference Aspect Ratio
    
    @Test func wallpaperStudioSupportsAppleModesGenerousRangeAndTrueAspectRatio() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "cot_r42_wp_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        
        let db = CotLocalDatabase(customURL: tempRoot.appending(path: "wp.sqlite3"))
        let manager = WallpaperManager(database: db, storageDirectory: tempRoot.appending(path: "imgs", directoryHint: .isDirectory))
        
        // Generous zoom (up to 4.0x), opacity (up to 0.85), blur (up to 40)
        manager.selectWallpaper(id: "ink-aurora", enableIfDisabled: true)
        manager.updateFraming(scale: 3.6, panX: -0.5, panY: 0.4, displayMode: .fill)
        manager.spec.opacity = 0.78
        manager.spec.blurRadius = 38.0
        #expect(abs(manager.spec.scale - 3.6) < 0.001)
        #expect(abs(manager.spec.opacity - 0.78) < 0.001)
        #expect(abs(manager.spec.blurRadius - 38.0) < 0.001)
        
        // Fit & Center modes allow zooming out below 1.0x down to 0.5x
        manager.updateFraming(scale: 0.65, panX: 0.25, panY: -0.25, displayMode: .fit)
        #expect(manager.spec.displayMode == .fit)
        #expect(abs(manager.spec.scale - 0.65) < 0.001)
        
        let fitRect = WallpaperManager.framedDrawRect(
            imageSize: CGSize(width: 1600, height: 900),
            viewportSize: CGSize(width: 400, height: 400),
            scale: 1.0,
            panX: 0.0,
            panY: 0.0,
            isFlippedY: true,
            displayMode: .fit
        )
        #expect(abs(fitRect.width - 400) < 0.5)
        #expect(abs(fitRect.height - 225) < 0.5)
        
        let centerDrag = WallpaperManager.dragUpdatedFraming(
            start: WallpaperFraming(scale: 0.8, panX: 0.0, panY: 0.0, displayMode: .center),
            imageSize: CGSize(width: 800, height: 600),
            viewportSize: CGSize(width: 400, height: 250),
            translation: CGSize(width: 40, height: -30)
        )
        #expect(centerDrag.displayMode == .center)
        #expect(centerDrag.panX < 0.0)
        #expect(centerDrag.panY > 0.0)
        
        let aspect = WallpaperManager.referenceWindowAspectRatio()
        #expect((1.15...2.25).contains(aspect))
    }
    
    
    // MARK: Test Image Helper
    
    private static func writePatternImage(
        to url: URL,
        size: NSSize,
        type: NSBitmapImageRep.FileType
    ) throws {
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
        NSColor.systemIndigo.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.systemOrange.setFill()
        NSRect(x: 0, y: 0, width: size.width * 0.5, height: size.height * 0.5).fill()
        NSGraphicsContext.restoreGraphicsState()
        let props: [NSBitmapImageRep.PropertyKey: Any] = (type == .jpeg) ? [.compressionFactor: 0.85] : [:]
        let data = try #require(rep.representation(using: type, properties: props))
        try data.write(to: url)
    }
}
