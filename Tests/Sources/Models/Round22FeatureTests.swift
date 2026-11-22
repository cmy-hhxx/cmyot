//
//  Round22FeatureTests.swift
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
struct Round22FeatureTests {
    
    // MARK: 1. Settings 12 Atomic Tabs + Wallpaper Tab + Concise CotPass
    
    @Test func settingsHasTwelveAtomicTabsIncludingWallpaperAndZeroYu() throws {
        
        let items = SidebarSettingsItem.allCases
        #expect(items.count == 12)
        #expect(items.contains(.wallpaper))
        #expect(SidebarSettingsItem.wallpaper.title == AppLanguage.text("壁纸", en: "Wallpaper"))
        
        for item in items {
            #expect(!item.title.contains("与"))
            #expect(!item.title.isEmpty)
        }
        
        let controller = SidebarSettingsWindowController()
        let window = try #require(controller.window)
        #expect(abs(window.contentLayoutRect.width - 780) <= 2)
        window.close()
    }
    
    
    @Test func brandLineEngineRespondsToPointer() {
        
        let centerLum = BrandLinePassEngine.luminance(normX: 0.5, normY: 0.5)
        let cornerLum = BrandLinePassEngine.luminance(normX: 0.02, normY: 0.02)
        #expect(centerLum >= cornerLum)
        
        let engine = BrandLinePassEngine()
        engine.step(time: 0.1, size: CGSize(width: 408, height: 246), pointer: CGPoint(x: 204, y: 123))
        engine.step(time: 0.13, size: CGSize(width: 408, height: 246), pointer: CGPoint(x: 212, y: 128))
        #expect(!engine.offsetX.isEmpty)
        #expect(!engine.activeDetections.isEmpty)
    }
    
    
    // MARK: 2. Wallpaper Manager Persistence & Custom Image Upload
    
    @Test func wallpaperManagerStoresCustomImageAndRendersBlurredBackdrop() throws {
        
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "cot_r22_wallpaper_\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        
        let db = CotLocalDatabase(customURL: tempRoot.appending(path: "test.sqlite3"))
        let storageDir = tempRoot.appending(path: "wallpapers", directoryHint: .isDirectory)
        let manager = WallpaperManager(database: db, storageDirectory: storageDir)
        
        #expect(WallpaperManager.builtInItems.count == 7)
        #expect(manager.spec.isEnabled == false)
        
        manager.spec.opacity = 0.99
        manager.spec.blurRadius = 64
        #expect(manager.spec.opacity <= 0.55)
        #expect(manager.spec.blurRadius <= 32.0)
        
        let testImage = NSImage(size: NSSize(width: 120, height: 80))
        testImage.lockFocus()
        NSColor.systemPurple.setFill()
        NSRect(origin: .zero, size: NSSize(width: 120, height: 80)).fill()
        testImage.unlockFocus()
        
        let customItem = try #require(manager.saveCustomWallpaper(testImage, title: "测试壁纸"))
        #expect(customItem.isCustom)
        #expect(manager.spec.isEnabled)
        #expect(manager.spec.selectedID == customItem.id)
        #expect(manager.activeBackdropImage() != nil)
        
        let reloaded = WallpaperManager(database: db, storageDirectory: storageDir)
        #expect(reloaded.allItems.contains(where: { $0.id == customItem.id }))
        
        reloaded.deleteCustomWallpaper(id: customItem.id)
        #expect(!reloaded.allItems.contains(where: { $0.id == customItem.id }))
    }
    
    
    // MARK: 3. Screen-Edge Clamped Avatar Floating Panel & AI Moe Companions
    
    @Test func anchoredPanelFrameNeverClipsPastRightOrBottomScreenEdges() {
        
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let topRightButton = NSRect(x: 1396, y: 842, width: 32, height: 28)
        let panelSize = NSSize(width: 344, height: 480)
        
        let anchored = UserAvatarToolbarButtonView.anchoredPanelFrame(
            buttonScreenRect: topRightButton,
            panelSize: panelSize,
            visibleScreenFrame: visibleFrame
        )
        #expect(anchored.minX >= visibleFrame.minX + 14)
        #expect(anchored.maxX <= visibleFrame.maxX - 14)
        #expect(anchored.minY >= visibleFrame.minY + 14)
        #expect(anchored.maxY <= visibleFrame.maxY - 14)
        
        let bottomButton = NSRect(x: 100, y: 12, width: 32, height: 28)
        let clampedBottom = UserAvatarToolbarButtonView.anchoredPanelFrame(
            buttonScreenRect: bottomButton,
            panelSize: panelSize,
            visibleScreenFrame: visibleFrame
        )
        #expect(clampedBottom.minY >= visibleFrame.minY + 14)
    }
    
    
    // MARK: 4. Analytics Candid Review Removes Document Names
    
    @Test func analyticsSanitizeCandidPointStripsDocumentTitlesAndBrackets() {
        
        let sample = "今天主要在折腾《深夜的水母》，深夜的水母那篇文档写得很顺，记得别拖延。"
        let cleaned = AnalyticsManager.sanitizeCandidPoint(sample, knownTitles: ["深夜的水母"])
        #expect(!cleaned.contains("深夜的水母"))
        #expect(!cleaned.contains("《"))
        #expect(!cleaned.contains("》"))
    }
    
    
    // MARK: 5. Notes Text Color Highlight Presets & Custom Hue Round-Trip
    
    @Test func highlightColorSupportsNineNotesPresetsAndCustomHueCodable() throws {
        
        #expect(HighlightColor.palettePresets == [.ivory, .rose, .yellow, .green, .cyan, .blue, .purple, .pink])
        
        let custom = HighlightColor.customHue(215.4)
        let mark = TextHighlight(location: 4, length: 12, color: custom)
        let encoded = try JSONEncoder().encode(mark)
        let decoded = try JSONDecoder().decode(TextHighlight.self, from: encoded)
        #expect(decoded == mark)
        #expect(decoded.color.rawValue == "hue:215.4")
        
        // Legacy raw names decode cleanly
        #expect(HighlightColor(rawValue: "yellow") == .yellow)
        #expect(HighlightColor(rawValue: "blue") == .blue)
        #expect(HighlightColor(rawValue: "orange") == .orange)
        
        // Dynamic colors resolve cleanly
        #expect(custom.noteTextColor.alphaComponent > 0.9)
        #expect(custom.backgroundColor.alphaComponent > 0.1)
    }
    
    
    // MARK: 6. Bounding Box Resize Morph & Anchored Geometry Math
    
    @Test func boundingBoxResizeMorphSpringAndAnchoredGeometryBehaveAccurately() throws {
        
        // InlineImageTransform custom dimensions clamp >= 64 × >= 48
        let minClamped = InlineImageTransform(customWidth: 20, customHeight: 12).clamped()
        #expect(minClamped.customWidth == 64)
        #expect(minClamped.customHeight == 48)
        
        // Encode/decode preserves customWidth & customHeight
        let explicit = InlineImageTransform(scale: 1.5, offsetX: 12, offsetY: 8, rotationDegrees: 15, customWidth: 320, customHeight: 180)
        let roundTripped = try JSONDecoder().decode(InlineImageTransform.self, from: JSONEncoder().encode(explicit))
        #expect(roundTripped == explicit)
        
        // 10-vertex morph square -> arrow interpolation
        let square = BoundingBoxHandleMorph.interpolatedVertices(for: .middleRight, progress: 0)
        let arrow = BoundingBoxHandleMorph.interpolatedVertices(for: .middleRight, progress: 1)
        #expect(square.count == 10)
        #expect(arrow.count == 10)
        #expect(abs(square[0].x - (-5)) < 0.001)
        #expect(abs(arrow[0].x - (-11)) < 0.001)
        #expect(abs(arrow[5].x - 11) < 0.001)
        
        // Damped spring converges smoothly to target 1.0
        var spring = BoundingBoxMorphSpring(value: 0, velocity: 0, target: 1)
        for _ in 0..<80 {
            _ = spring.step(dt: 1.0 / 60.0)
        }
        #expect(abs(spring.value - 1.0) < 0.01)
        
        // West handle drag anchors right edge and clamps minimum width at 64
        let start = NSRect(x: 120, y: 24, width: 280, height: 200)
        let shrunkWest = BoundingBoxResizeMath.resizedFrame(
            startFrame: start,
            handle: .middleLeft,
            delta: NSPoint(x: 500, y: 0),
            minXBound: 16,
            minYBound: 16,
            maxXBound: 608,
            maxYBound: 600
        )
        #expect(shrunkWest.width == 64)
        #expect(shrunkWest.maxX == start.maxX)
        #expect(shrunkWest.height == start.height)
    }
}
