//
//  Round27FeatureTests.swift
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
struct Round27FeatureTests {
    
    // MARK: 1. AppIconManager Live Preview Revision, Clamping & Corner Badge Removal
    
    @Test func appIconLiveUpdatesIncrementPreviewRevisionAndDoNotRenderCornerBadge() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "CotR27Icons-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "icons.sqlite3"))
        let iconDir = tempDir.appending(path: "CustomAppIcon", directoryHint: .isDirectory)
        let manager = AppIconManager(database: db, storageDirectory: iconDir)
        
        let initialRev = manager.previewRevision
        manager.updateSpecLive { spec in
            spec.imageZoom = 1.80 // out-of-range should clamp to 1.35
            spec.cornerRoundness = 0.05 // should clamp to 0.16
            spec.borderStyle = .ultraViolet
        }
        #expect(manager.previewRevision > initialRev)
        #expect(abs(manager.spec.imageZoom - 1.35) < 0.001)
        #expect(abs(manager.spec.cornerRoundness - 0.16) < 0.001)
        
        // Visual rendering must no longer draw corner badge medallions even if an old spec carries .crown
        var cleanSpec = manager.spec
        cleanSpec.cornerBadge = .none
        var crownSpec = manager.spec
        crownSpec.cornerBadge = .crown
        
        let cleanData = try #require(manager.renderIcon(spec: cleanSpec, size: 128).tiffRepresentation)
        let crownData = try #require(manager.renderIcon(spec: crownSpec, size: 128).tiffRepresentation)
        #expect(cleanData == crownData)
    }
    
    
    // MARK: 2. Wallpaper Legacy Decode, Per-Item Crop Persistence & Flipped/Unflipped Equivalence
    
    @Test func wallpaperFramingDecodesLegacyJSONPersistsPerItemAndMatchesFlippedUnflippedMath() throws {
        let legacyJSON = Data("""
        {"isEnabled":true,"selectedID":"starry-indigo","opacity":0.24,"blurRadius":12.0}
        """.utf8)
        let decoded = try JSONDecoder().decode(WallpaperSpec.self, from: legacyJSON)
        #expect(decoded.isEnabled == true)
        #expect(decoded.selectedID == "starry-indigo")
        #expect(decoded.scale == 1.0)
        #expect(decoded.panX == 0.0)
        #expect(decoded.panY == 0.0)
        
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "cot_r27_wall_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        
        let db = CotLocalDatabase(customURL: tempRoot.appending(path: "wall.sqlite3"))
        let manager = WallpaperManager(database: db, storageDirectory: tempRoot.appending(path: "imgs"))
        manager.selectWallpaper(id: "ink-aurora", enableIfDisabled: true)
        manager.updateFraming(scale: 1.75, panX: -0.45, panY: 0.62)
        
        manager.selectWallpaper(id: "amber-dawn", enableIfDisabled: true)
        #expect(manager.spec.scale == 1.0)
        #expect(manager.spec.panY == 0.0)
        
        manager.selectWallpaper(id: "ink-aurora", enableIfDisabled: true)
        #expect(abs(manager.spec.scale - 1.75) < 0.001)
        #expect(abs(manager.spec.panX - (-0.45)) < 0.001)
        #expect(abs(manager.spec.panY - 0.62) < 0.001)
        
        // Verify framedDrawRect equivalence between SwiftUI (flippedY = true) and AppKit NSView (flippedY = false)
        let img = CGSize(width: 1000, height: 2000)
        let view = CGSize(width: 400, height: 200)
        
        // panY = -1 should pin the TOP of the image to the top of the viewport in both coordinate systems
        let topSwiftUI = WallpaperManager.framedDrawRect(imageSize: img, viewportSize: view, scale: 1.4, panX: 0, panY: -1.0, isFlippedY: true)
        let topAppKit = WallpaperManager.framedDrawRect(imageSize: img, viewportSize: view, scale: 1.4, panX: 0, panY: -1.0, isFlippedY: false)
        #expect(abs(topSwiftUI.minY - 0) < 0.01) // SwiftUI top is 0
        #expect(abs(topAppKit.maxY - view.height) < 0.01) // AppKit top is view.height
        #expect(abs(topSwiftUI.height - topAppKit.height) < 0.01)
        
        // panY = +1 should pin the BOTTOM of the image to the bottom of the viewport in both coordinate systems
        let botSwiftUI = WallpaperManager.framedDrawRect(imageSize: img, viewportSize: view, scale: 1.4, panX: 0, panY: 1.0, isFlippedY: true)
        let botAppKit = WallpaperManager.framedDrawRect(imageSize: img, viewportSize: view, scale: 1.4, panX: 0, panY: 1.0, isFlippedY: false)
        #expect(abs(botSwiftUI.maxY - view.height) < 0.01) // SwiftUI bottom is view.height
        #expect(abs(botAppKit.minY - 0) < 0.01) // AppKit bottom is 0
    }
    
    
    // MARK: 3. Done-Today & Next-Actions Strip All Word Counts, Document Names & Stay Single-Line
    
    @Test func dashboardActionCardsStripDocumentTitlesAndWordCountsAndClampSingleLine() throws {
        let rawLine = "推进《架构重构白皮书》(3,480 字)，手写输入 1,240 字，完善核心结论.md"
        let sanitized = AnalyticsManager.sanitizeDashboardActionText(
            rawLine,
            knownTitles: ["架构重构白皮书", "核心结论.md"],
            maxLength: 16,
            fallback: "推进核心内容梳理"
        )
        #expect(!sanitized.contains("架构重构白皮书"))
        #expect(!sanitized.contains("核心结论"))
        #expect(!sanitized.contains("《"))
        #expect(!sanitized.contains("字"))
        #expect(sanitized.count <= 16)
        
        let doc = StoredDocumentRecord(
            id: "doc-plan",
            title: "季度产品规划书.md",
            filePath: nil,
            syntax: "Markdown",
            content: "# 目标\n- [ ] 补全灰度发布与异常回滚演练的验证流程清单\n是否需要补充跨区域灾备演练？",
            highlightsJSON: "[]",
            updatedAt: Date(),
            createdAt: Date()
        )
        let heuristic = AnalyticsManager.buildHeuristicActionPredictions(
            documents: [doc],
            weeklyReports: [],
            reminders: []
        )
        #expect(!heuristic.isEmpty)
        #expect(heuristic.contains { $0.sourceDocumentID == "doc-plan" })
        for pred in heuristic {
            #expect(AnalyticsManager.isCompleteDashboardSentence(pred.action))
            #expect(!pred.action.contains("季度产品规划书"))
            #expect(!pred.action.contains("《"))
            #expect(!pred.action.contains("字"))
            #expect(pred.reason.isEmpty)
        }
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "CotR27Analytics-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "analytics.sqlite3"))
        db.saveDocument(id: doc.id, title: doc.title, filePath: doc.filePath, syntax: doc.syntax, content: doc.content)
        let analytics = AnalyticsManager(database: db)
        analytics.recordTypedCharacters(420)
        analytics.recordDocumentSaved()
        
        for line in analytics.doneTodayPoints {
            #expect(!line.contains("季度产品规划书"))
            #expect(!line.contains("《"))
            #expect(line.range(of: #"\d[\d,.\s]*字"#, options: .regularExpression) == nil)
        }
        
        let snapshot = DashboardSnapshot.build(
            analytics: analytics,
            selectedYear: Calendar.current.component(.year, from: Date()),
            version: 1
        )
        #expect(snapshot.snapshotVersion == 1)
        #expect(!snapshot.trendCurve14.samples.isEmpty)
        #expect(!snapshot.sunburstIndex.isEmpty)
        #expect(snapshot.sunburstIndex["root"] != nil)
    }
}
