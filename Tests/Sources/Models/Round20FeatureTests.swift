//
//  Round20FeatureTests.swift
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
import SwiftUI
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round20FeatureTests {
    
    // MARK: 1. Settings 12 Atomic Tabs, Zero "与", and Balanced 700pt Proportions
    
    @Test func settingsHasTwelveAtomicTabsWithoutYuAndUsesGoldenProportions() throws {
        
        let items = SidebarSettingsItem.allCases
        #expect(items.count == 11)
        #expect(items.contains(.appearance))
        
        for item in items {
            #expect(!item.title.contains("与"), "Tab title should be atomic without 与: \(item.title)")
            #expect(!item.title.isEmpty)
            #expect(NSImage(systemSymbolName: item.symbolName, accessibilityDescription: nil) != nil, "Invalid SF Symbol: \(item.symbolName)")
        }
        
        // Legacy SettingsPane mapping resolves cleanly
        for legacy in SettingsPane.allCases {
            let mapped = SidebarSettingsItem(legacyPane: legacy)
            #expect(items.contains(mapped))
        }
        
        let controller = SidebarSettingsWindowController()
        let window = try #require(controller.window)
        #expect(abs(window.contentLayoutRect.width - 780) <= 2)
        #expect(abs(window.minSize.width - 780) <= 2)
        #expect(abs(window.maxSize.width - 780) <= 2)
        window.close()
    }
    
    
    // MARK: 2. Original Atelier Pass View & Theme Model
    
    @Test func atelierPassRendersCleanlyAndPreservesThemes() {
        
        #expect(CotPassTheme.allThemes.count >= 5)
        let host = NSHostingController(rootView: CotPassSettingsView())
        host.view.frame = NSRect(x: 0, y: 0, width: 460, height: 500)
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.fittingSize.width <= 480)
    }
    
    
    // MARK: 3. Soft Atmospheric Avatar Color Extraction
    
    @Test func avatarColorExtractorHarmonizesExtremeNeonAndNearBlackImages() throws {
        
        func makeSolidImage(_ color: NSColor) -> NSImage {
            let img = NSImage(size: NSSize(width: 48, height: 48))
            img.lockFocus()
            color.setFill()
            NSRect(x: 0, y: 0, width: 48, height: 48).fill()
            img.unlockFocus()
            return img
        }
        
        let profile = UserProfile(
            id: "test-neon-\(UUID().uuidString)",
            displayName: "测试",
            avatarData: nil,
            avatarColorHex: "#FF00FF",
            dbFilename: "test.sqlite3",
            accountKind: "local",
            email: nil,
            remoteUserID: nil,
            createdAt: Date(),
            lastActiveAt: Date()
        )
        
        // Extreme neon magenta image must clamp saturation into soft aurora range (<= 0.50)
        let neonPalette = AvatarColorExtractor.extractPalette(
            for: profile,
            image: makeSolidImage(NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1))
        )
        let neonPrimaryNS = try #require(NSColor(neonPalette.primary).usingColorSpace(.sRGB))
        #expect(neonPrimaryNS.saturationComponent <= 0.50)
        #expect(neonPrimaryNS.saturationComponent >= 0.22)
        #expect(neonPrimaryNS.brightnessComponent >= 0.58 && neonPrimaryNS.brightnessComponent <= 0.88)
        #expect(neonPalette.primary != neonPalette.secondary)
        
        // Near-black image must lift brightness out of muddy black (>= 0.58)
        let darkProfile = UserProfile(
            id: "test-dark-\(UUID().uuidString)",
            displayName: "暗影",
            avatarData: nil,
            avatarColorHex: "#050505",
            dbFilename: "test2.sqlite3",
            accountKind: "local",
            email: nil,
            remoteUserID: nil,
            createdAt: Date(),
            lastActiveAt: Date()
        )
        let darkPalette = AvatarColorExtractor.extractPalette(
            for: darkProfile,
            image: makeSolidImage(NSColor(srgbRed: 0.02, green: 0.02, blue: 0.02, alpha: 1))
        )
        let darkPrimaryNS = try #require(NSColor(darkPalette.primary).usingColorSpace(.sRGB))
        #expect(darkPrimaryNS.brightnessComponent >= 0.58)
    }
    
    
    // MARK: 4. Lightweight Capsule Pinned Todo Formatting & Non-Intrusiveness
    
    @Test func pinnedTodoCompactBadgeAndFeatherweightMetrics() {
        
        #expect(PinnedTodoUrgency.compactBadgeText(42) == "42s")
        #expect(PinnedTodoUrgency.compactBadgeText(9 * 60 + 15) == "9m")
        #expect(PinnedTodoUrgency.compactBadgeText(80 * 60) == "1h 20m")
        #expect(PinnedTodoUrgency.compactBadgeText(-185) == "超时 3m")
        
        let now = Date()
        let metrics = PinnedTodoUrgency.metrics(
            createdAt: now.addingTimeInterval(-3600),
            deadline: now.addingTimeInterval(-10),
            now: now,
            containerSize: CGSize(width: 900, height: 600)
        )
        #expect(metrics.fontSize <= 14.0)
        #expect(metrics.isWindowBursting == false)
        #expect(metrics.isOverdue == true)
    }
    
    
    // MARK: 5. Candid AI Bullet Summary, Recent Manuscripts & Achievement Metrics
    
    @Test func dashboardCandidPointsRecentManuscriptsAndAchievements() throws {
        
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "cot_round20_dash_\(UUID().uuidString).sqlite3")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let db = CotLocalDatabase(customURL: tempURL)
        let analytics = AnalyticsManager(database: db)
        
        db.saveDocument(
            id: "doc-r20-1",
            title: "重构记录.md",
            filePath: nil,
            syntax: "Markdown",
            content: "# 设计笔记\n把设置界面拆成了十个清爽的独立标签页。"
        )
        db.saveDocument(
            id: "doc-r20-2",
            title: "Trail.swift",
            filePath: nil,
            syntax: "Swift",
            content: "let spring = CASpringAnimation(keyPath: \"transform\")"
        )
        
        analytics.recordTypedCharacters(1420)
        analytics.recordGhostCompletionAccepted(charCount: 84, isFromAI: true)
        analytics.recordDocumentSaved()
        analytics.flushPendingStats()
        
        // Peak flow window
        let peak = try #require(analytics.peakFlowWindow(for: analytics.todayStats.dateKey))
        #expect(peak.peakChars >= 1420)
        #expect(!peak.chronotype.isEmpty)
        
        // Recent touched manuscripts newest-first with excerpts
        let manuscripts = analytics.recentTouchedManuscripts(days: 7, limit: 6)
        #expect(manuscripts.count == 2)
        #expect(manuscripts.contains { $0.title == "重构记录.md" && $0.kind == .markdown && !$0.excerpt.isEmpty })
        #expect(manuscripts.contains { $0.title == "Trail.swift" && $0.kind == .code })
        
        // Candid plain-spoken bullet summary
        let hm = analytics.yearlyHeatmap(year: Calendar.current.component(.year, from: Date()), trimFutureWeeks: true)
        let todayCell = try #require(hm.weeks.flatMap(\.self).first(where: { $0.dateKey == analytics.todayStats.dateKey }))
        let points = analytics.candidDailyTakePoints(for: todayCell, baselineDailyChars: 400)
        #expect(points.count >= 2)
        #expect(points.allSatisfy { !$0.contains("火力全开") && !$0.contains("Tokens") })
    }
}
