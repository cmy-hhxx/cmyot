//
//  Round21FeatureTests.swift
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
struct Round21FeatureTests {
    
    // MARK: 1. Global Designer 3-Color Studio Palettes
    
    @Test func studioPaletteManagerProvidesDesignerTriadsAndPersists() throws {
        
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "cot_r21_palette_\(UUID().uuidString).sqlite3")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let db = CotLocalDatabase(customURL: tempURL)
        let manager = StudioPaletteManager(database: db)
        
        // Check exact hex values matching the 3 curated editorial reference palettes
        let uv = manager.triad(for: .ultraViolet)
        #expect(uv.darkInkHex == "#0E0E16")
        #expect(uv.lightPaperHex == "#E7E7E7")
        #expect(uv.accentHex == "#715CB2")
        
        let crimson = manager.triad(for: .signalCrimson)
        #expect(crimson.lightPaperHex == "#EAEAEA")
        #expect(crimson.darkInkHex == "#111111")
        #expect(crimson.accentHex == "#D53740")
        
        let matcha = manager.triad(for: .matchaParchment)
        #expect(matcha.lightPaperHex == "#E7DBB8")
        #expect(matcha.darkInkHex == "#121212")
        #expect(matcha.accentHex == "#A4CE46")
        
        manager.selectPalette(.matchaParchment)
        let reloaded = StudioPaletteManager(database: db)
        #expect(reloaded.selectedID == .matchaParchment)
        
        let lightTokens = reloaded.tokens(isDark: false)
        let darkTokens = reloaded.tokens(isDark: true)
        #expect(lightTokens.isDark == false)
        #expect(darkTokens.isDark == true)
    }
    
    
    // MARK: 2. Chiikawa App Icon Studio & Gold Inlay Rendering
    
    @Test func appIconManagerRendersGoldInlaySupportsCustomUploadAndPersists() throws {
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "CotR21Icons-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "icons.sqlite3"))
        let iconDir = tempDir.appending(path: "CustomAppIcon", directoryHint: .isDirectory)
        let manager = AppIconManager(database: db, storageDirectory: iconDir)
        
        #expect(manager.spec.borderStyle == .goldInlay)
        let rendered = manager.renderIcon(size: 512)
        #expect(rendered.size.width == 512)
        #expect(rendered.size.height == 512)
        
        // Customize with a test artwork & obsidian-gold border
        let sampleArt = NSImage(size: NSSize(width: 64, height: 64))
        sampleArt.lockFocus()
        NSColor.systemPurple.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        sampleArt.unlockFocus()
        
        #expect(manager.saveCustomImage(sampleArt) == true)
        #expect(manager.hasCustomImage == true)
        manager.spec.borderStyle = .obsidianGold
        manager.spec.cornerBadge = .crown
        manager.spec.imageZoom = 1.18
        
        let reloaded = AppIconManager(database: db, storageDirectory: iconDir)
        #expect(reloaded.spec.source == .customImage)
        #expect(reloaded.spec.borderStyle == .obsidianGold)
        #expect(reloaded.spec.cornerBadge == .crown)
        #expect(abs(reloaded.spec.imageZoom - 1.18) < 0.001)
    }
    
    
    // MARK: 3. Inline Image Stepless Zoom, Offset, Rotation & Right-Click Menu
    
    @Test func inlineImageSteplessTransformPersistsExpandsGeometryAndBuildsRightClickMenu() throws {
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "CotR21ImgTx-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let docURL = tempDir.appending(path: "doc.txt")
        try Data().write(to: docURL)
        
        let sampleImage = NSImage(size: NSSize(width: 240, height: 160))
        sampleImage.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 240, height: 160).fill()
        sampleImage.unlockFocus()
        
        let stored = try #require(PlainTextInlineImageStore.shared.store(image: sampleImage, for: docURL))
        let identifier = stored.token
            .replacingOccurrences(of: "⟦🖼 ", with: "")
            .replacingOccurrences(of: "⟧", with: "")
        
        let baseGeom = try #require(PlainTextInlineImageStore.shared.displayGeometry(
            for: identifier,
            documentURL: docURL,
            containerWidth: 900
        ))
        #expect(baseGeom.transform.isIdentity == true)
        
        // Apply stepless scale 2.4x (exceeding default 460pt cap on wide 900pt canvas), offset, and 37° rotation
        let customTx = InlineImageTransform(scale: 2.4, offsetX: 85, offsetY: 24, rotationDegrees: 37)
        PlainTextInlineImageStore.shared.setTransform(customTx, for: identifier, documentURL: docURL)
        
        let updatedGeom = try #require(PlainTextInlineImageStore.shared.displayGeometry(
            for: identifier,
            documentURL: docURL,
            containerWidth: 900
        ))
        #expect(updatedGeom.drawSize.width > baseGeom.drawSize.width)
        #expect(updatedGeom.drawSize.width > 460)
        #expect(updatedGeom.rotatedBoxSize.height > updatedGeom.drawSize.height)
        #expect(updatedGeom.cardSize.height > updatedGeom.rotatedBoxSize.height + 24)
        
        // Right-click menu exposes zoom preview + transform panel + rotation/alignment actions
        let doc = Document()
        doc.fileURL = docURL
        let textView = EditorTextView(textStorage: doc.textStorage, lineEndingScanner: doc.lineEndingScanner)
        let menu = textView.makeInlineImageContextMenu(for: identifier, tokenRange: NSRange(location: 0, length: (stored.token as NSString).length))
        let titles = menu.items.map(\.title)
        #expect(titles.contains(where: { $0.contains("大图") || $0.contains("Zoom") }))
        #expect(titles.contains(where: { $0.contains("旋转") || $0.contains("Rotate") }))
        #expect(titles.contains(where: { $0.contains("大小") || $0.contains("Transform") || $0.contains("Adjust") }))
    }
    
    
    // MARK: 4. Danmaku Strict Label Deduplication
    
    @Test func danmakuTagsStrictlyDeduplicate() {
        
        let raw = [
            UserPersonalityTag(id: "1", label: "  夜深灵感  ", explanation: "a", tone: .calm),
            UserPersonalityTag(id: "2", label: "夜深灵感", explanation: "b", tone: .warm),
            UserPersonalityTag(id: "3", label: "ReactPro", explanation: "c", tone: .sharp),
            UserPersonalityTag(id: "4", label: "reactpro", explanation: "d", tone: .playful),
            UserPersonalityTag(id: "5", label: "条理清晰", explanation: "e", tone: .calm),
        ]
        let deduped = UserPersonalityAnalyzer.deduplicatedTags(raw)
        #expect(deduped.count == 3)
        #expect(deduped.map(\.label) == ["夜深灵感", "ReactPro", "条理清晰"])
    }
    
    
    // MARK: 5. AppLanguage Defaults Strictly to Simplified Chinese Unless Explicitly Switched to English
    
    @Test func appLanguageAlwaysDefaultsToChineseUnlessExplicitlyEnglish() {
        
        let suiteName = "local.cmy.Cot.Round21LangTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        
        // Even if system AppleLanguages starts with "en", app stays Simplified Chinese until explicit setting
        defaults.set(["en-US"], forKey: "AppleLanguages")
        #expect(AppLanguage.current(in: defaults) == .simplifiedChinese)
        
        AppLanguage.english.apply(to: defaults)
        #expect(AppLanguage.current(in: defaults) == .english)
        
        AppLanguage.simplifiedChinese.apply(to: defaults)
        #expect(AppLanguage.current(in: defaults) == .simplifiedChinese)
    }
}
