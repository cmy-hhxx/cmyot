//
//  Round24FeatureTests.swift
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

@MainActor
struct Round24FeatureTests {
    
    // MARK: 1. Highlight Palette Whitespace Guard
    
    @Test func highlightPaletteIgnoresWhitespaceAndEmptySelections() {
        #expect(!NotesTextColorPaletteController.shouldPresent(for: ""))
        #expect(!NotesTextColorPaletteController.shouldPresent(for: "   "))
        #expect(!NotesTextColorPaletteController.shouldPresent(for: "\t\n  \r\n"))
        #expect(!NotesTextColorPaletteController.shouldPresent(for: "⟦🖼demo-id⟧"))
        #expect(NotesTextColorPaletteController.shouldPresent(for: "hello"))
        #expect(NotesTextColorPaletteController.shouldPresent(for: "  中文高亮  "))
        
        // Highlighting is right-click only and never auto-opens on selection
        #expect(!NotesTextColorPaletteController.shared.isVisible)
    }
    
    
    // MARK: 2. Vim j/k Sticky Column Across Blank & Shorter Lines
    
    @Test func vimVerticalMovementPreservesColumnAcrossBlankAndShortLines() throws {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.string = "0123456789abcdef\n\nhi\nABCDEFGHIJKLMNOP"
        
        let engine = VimEngine(textView: textView)
        VimState.shared.mode = .normal
        
        // Start on line 3 ("ABCDEFGHIJKLMNOP") at column 8 ('I')
        let line3Start = ("0123456789abcdef\n\nhi\n" as NSString).length
        textView.setSelectedRange(NSRange(location: line3Start + 8, length: 0))
        
        // Press `k` -> lands on short line "hi" (clamped to index 1, 'i')
        let kEvent = try Self.makeKeyEvent(char: "k", keyCode: 40)
        #expect(engine.handleKeyDown(kEvent))
        let line2Start = ("0123456789abcdef\n\n" as NSString).length
        #expect(textView.selectedRange().location == line2Start + 1)
        
        // Press `k` -> lands on blank line (offset 0)
        #expect(engine.handleKeyDown(kEvent))
        let line1Start = ("0123456789abcdef\n" as NSString).length
        #expect(textView.selectedRange().location == line1Start)
        
        // Press `k` -> restores sticky column ~8 on line 0 ("0123456789abcdef") instead of snapping to column 0!
        #expect(engine.handleKeyDown(kEvent))
        #expect(textView.selectedRange().location >= 7 && textView.selectedRange().location <= 9)
        
        // Press `j` three times back to line 3 -> stays near column 8!
        let jEvent = try Self.makeKeyEvent(char: "j", keyCode: 38)
        #expect(engine.handleKeyDown(jEvent))
        #expect(engine.handleKeyDown(jEvent))
        #expect(engine.handleKeyDown(jEvent))
        let finalCol = textView.selectedRange().location - line3Start
        #expect(finalCol >= 7 && finalCol <= 9)
    }
    
    
    // MARK: 3. Toolbar Capsule Todos: Priority Ordering & Always-On Time Badge
    
    @Test func toolbarCapsuleTodosPrioritizeSoonestAndAlwaysShowTime() {
        let now = Date()
        let todayKey = AnalyticsManager.dateKey(for: now)
        let timeless = UserReminder(
            id: "timeless",
            title: "无期限任务",
            dueDate: now.addingTimeInterval(9999),
            dueDayKey: todayKey,
            createdAt: now.addingTimeInterval(-600),
            isPinned: true,
            hasDeadline: false
        )
        let later = UserReminder(
            id: "later",
            title: "两小时后",
            dueDate: now.addingTimeInterval(7200),
            dueDayKey: todayKey,
            createdAt: now.addingTimeInterval(-300),
            isPinned: true,
            hasDeadline: true
        )
        let soon = UserReminder(
            id: "soon",
            title: "10分钟内到期",
            dueDate: now.addingTimeInterval(600),
            dueDayKey: todayKey,
            createdAt: now.addingTimeInterval(-100),
            isPinned: true,
            hasDeadline: true
        )
        let overdue = UserReminder(
            id: "overdue",
            title: "已超时事项",
            dueDate: now.addingTimeInterval(-120),
            dueDayKey: todayKey,
            createdAt: now.addingTimeInterval(-900),
            isPinned: true,
            hasDeadline: true
        )
        
        let sorted = ToolbarCapsuleTodoHelper.prioritizedTodos([timeless, later, soon, overdue])
        #expect(sorted.map(\.id) == ["later", "soon", "overdue", "timeless"])
        
        // Every item, including timeless ones, produces a non-empty time badge
        for item in sorted {
            let badge = ToolbarCapsuleTodoHelper.timeBadgeText(for: item, now: now)
            #expect(!badge.isEmpty)
        }
    }
    
    
    // MARK: 4. AI Gijinka Model-Driven Resolution
    
    @Test func aiGijinkaResolvesStrictlyFromSelectedModel() {
        #expect(AIGijinkaCharacter.resolve(modelName: "deepseek-chat") == .deepseek)
        #expect(AIGijinkaCharacter.resolve(modelName: "anthropic/claude-3.7-sonnet", endpointName: "OpenRouter", baseURL: "https://openrouter.ai/api/v1") == .claude)
        #expect(AIGijinkaCharacter.resolve(modelName: "qwen-max") == .qwen)
        #expect(AIGijinkaCharacter.resolve(modelName: "gpt-4o-mini") == .gpt)
        #expect(AIGijinkaCharacter.resolve(modelName: "gemini-2.5-pro") == .gemini)
        #expect(AIGijinkaCharacter.resolve(modelName: "moonshot-v1-8k") == .kimi)
        #expect(AIGijinkaCharacter.resolve(modelName: "glm-4-plus") == .glm)
        #expect(AIGijinkaCharacter.resolve(modelName: "MiniMax-Text-01") == .minimax)
        #expect(AIGijinkaCharacter.resolve(modelName: "grok-3") == .grok)
        #expect(AIGijinkaCharacter.resolve(modelName: "doubao-seed-1.6") == .seed)
        #expect(AIGijinkaCharacter.resolve(modelName: "meta-llama/llama-3.3-70b") == .llama)
        #expect(AIGijinkaCharacter.resolve(modelName: "mistral-large") == .mistral)
        #expect(AIGijinkaCharacter.resolve(modelName: "sonar-pro") == .perplexity)
        #expect(AIGijinkaCharacter.resolve(modelName: "custom-model", endpointName: "DeepSeek", baseURL: "https://api.deepseek.com/v1") == .deepseek)
        #expect(AIGijinkaCharacter.resolve(modelName: "my-unknown-local-model") == nil)
        #expect(AIGijinkaCharacter.resolve(modelName: nil) == nil)
        
        for character in AIGijinkaCharacter.allCharacters {
            #expect(character.portraitURL != nil)
            #expect(character.portraitURLString.hasPrefix("https://"))
        }
    }
    
    
    // MARK: 4B. User Profile Popover Bounded Fitting Height (No Background Overflow)
    
    @Test func userProfilePopoverStaysWithinExpectedHeightBounds() {
        let controller = NSHostingController(rootView: UserProfilePopoverView())
        let size = controller.sizeThatFits(in: CGSize(width: 348, height: 600))
        #expect(abs(size.width - 348) <= 2)
        #expect(size.height >= 240 && size.height <= 420)
        
        // Verify Apple Music cover-art backdrop with an oversized image never inflates parent VStack fittingSize
        let largeCover = NSImage(size: NSSize(width: 512, height: 512))
        largeCover.lockFocus()
        NSColor.systemIndigo.setFill()
        NSRect(x: 0, y: 0, width: 512, height: 512).fill()
        largeCover.unlockFocus()
        
        let palette = AvatarColorExtractor.Palette(primary: .blue, secondary: .purple, tertiary: .teal)
        let card = VStack {
            Text("Header").frame(height: 20)
            Color.clear.frame(height: 180)
        }
        .frame(width: 328)
        .background {
            SoftAvatarAuroraBackdrop(
                palette: palette,
                blurredCoverImage: largeCover,
                surface: .clear,
                isDark: true
            )
        }
        let cardController = NSHostingController(rootView: card)
        let cardSize = cardController.sizeThatFits(in: CGSize(width: 328, height: 600))
        #expect(abs(cardSize.width - 328) <= 2)
        #expect(cardSize.height >= 200 && cardSize.height <= 230)
    }
    
    
    // MARK: 5. CotPass Metadata, Blue Fluted Glass & Avatar Contour Extraction
    
    @Test func cotPassTierFieldsAndAvatarContourLuminanceField() throws {
        #expect(CotPassTier.explorer.statusLabel == "LANDED")
        #expect(CotPassTier.pro.statusLabel == "LANDED")
        #expect(CotPassTier.explorer.accessLabel == "Free")
        #expect(CotPassTier.pro.accessLabel == "FULL")
        #expect(CotPassTier.founder.accessLabel == "FULL")
        #expect(CotPassTier.explorer.summaryLabel == "Free")
        #expect(CotPassTier.pro.summaryLabel == "FULL")
        #expect(CotPassTier.founder.summaryLabel == "FULL")
        
        // Blue Fluted Glass backdrop renders valid RGBA frame with expected dimensions
        let flutedFrame = try #require(BlueFlutedGlassRenderer.renderFrame(time: 4.2, width: 64, height: 40))
        #expect(flutedFrame.width == 64)
        #expect(flutedFrame.height == 40)
        
        // Render a synthetic high-contrast portrait image and confirm Sobel contour extraction produces signal
        let avatar = NSImage(size: NSSize(width: 96, height: 96))
        avatar.lockFocus()
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 96, height: 96).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 20, y: 20, width: 56, height: 56)).fill()
        avatar.unlockFocus()
        
        let field = BrandLinePassEngine.buildAvatarContourField(from: avatar)
        #expect(field.count == BrandLinePassEngine.gridSize * BrandLinePassEngine.gridSize)
        #expect((field.max() ?? 0) > 0.5)
    }
    
    
    // MARK: 5B. Cross-Endpoint Agent Routing, Multi-Artwork Diversity & Popover Rounded Mask
    
    @Test func agentCrossEndpointRoutingMultiArtworkDiversityAndPopoverMask() throws {
        // 1. Popover rounded mask is 9-slice stretchable (prevents square white corner bleed)
        let mask = UserAvatarToolbarButtonView.makeRoundedMaskImage(cornerRadius: 16)
        #expect(mask.resizingMode == .stretch)
        #expect(mask.capInsets.top == 16 && mask.capInsets.left == 16)
        
        // 2. Multi-artwork diversity: agents sharing DeepSeek / GPT get varied artworks by default
        #expect(AIGijinkaCharacter.deepseek.artworks.count >= 8)
        #expect(AIGijinkaCharacter.gpt.artworks.count >= 5)
        let artA = AIGijinkaCharacter.deepseek.artwork(for: .ghost)
        let artB = AIGijinkaCharacter.deepseek.artwork(for: .translate)
        let artC = AIGijinkaCharacter.deepseek.artwork(for: .summarize)
        #expect(artA.id != artB.id)
        #expect(artB.id != artC.id)
        #expect(AIGijinkaCharacter.deepseek.artwork(for: .ghost, variantOverride: 4).id == AIGijinkaCharacter.deepseek.artworks[4].id)
        
        // 3. Per-bot endpointID + modelOverride routes cleanly across endpoints
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "cot_r24_bot_routing_\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        
        let db = CotLocalDatabase(customURL: tempRoot.appending(path: "test.sqlite3"))
        let store = AIBotStore(database: db)
        let anthropicEndpoint = AIEndpointProfile(
            name: "Anthropic Work",
            endpoint: .anthropicMessages,
            baseURL: "https://api.anthropic.com/v1",
            model: "claude-3-7-sonnet",
            savedModels: ["claude-3-7-sonnet", "claude-3-5-haiku"]
        )
        let deepSeekEndpoint = AIEndpointProfile(
            name: "DeepSeek Default",
            endpoint: .openAIChatCompletions,
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-chat"
        )
        store.updateConfig(
            AIBotConfig(
                isEnabled: true,
                endpointID: anthropicEndpoint.id,
                modelOverride: "claude-3-5-haiku",
                artworkVariantIndex: 1
            ),
            for: .translate
        )
        
        let resolved = store.resolvedConfiguration(
            for: .translate,
            baseConfig: deepSeekEndpoint.configuration(apiKey: "ds-key"),
            endpoints: [deepSeekEndpoint, anthropicEndpoint]
        )
        #expect(resolved.endpoint == .anthropicMessages)
        #expect(resolved.baseURL == "https://api.anthropic.com/v1")
        #expect(resolved.model == "claude-3-5-haiku")
    }
    
    
    // MARK: 6. Apple Music Ambient Blurred Cover Artwork
    
    @Test func avatarColorExtractorBuildsAppleMusicBlurredAmbientArtwork() {
        let avatar = NSImage(size: NSSize(width: 80, height: 80))
        avatar.lockFocus()
        NSColor.systemPink.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 80).fill()
        NSColor.systemTeal.setFill()
        NSRect(x: 40, y: 0, width: 40, height: 80).fill()
        avatar.unlockFocus()
        
        let profile = UserProfile(
            id: "ambient-test",
            displayName: "Tester",
            avatarData: Data([1, 2, 3]),
            avatarColorHex: "#715CB2",
            dbFilename: "test.sqlite3",
            accountKind: "local",
            email: nil,
            remoteUserID: nil,
            createdAt: Date(),
            lastActiveAt: Date()
        )
        let blurred = AvatarColorExtractor.blurredAmbientArtwork(for: profile, image: avatar)
        #expect(blurred != nil)
        #expect((blurred?.size.width ?? 0) > 0)
    }
    
    
    // MARK: 7. Database Migration Studio Theme Synthesis (Zero Missing Resource Alerts)
    
    @Test func studioPaletteThemesSynthesizeOnDemandAfterMigration() throws {
        let cnDark = "Studio · 电光紫罗兰 (暗色)"
        let enLight = "Studio · Matcha Marker (Light)"
        
        let theme1 = StudioPaletteManager.shared.synthesizedTheme(named: cnDark)
        let theme2 = StudioPaletteManager.shared.synthesizedTheme(named: enLight)
        #expect(theme1 != nil)
        #expect(theme2 != nil)
        #expect(StudioPaletteManager.shared.synthesizedTheme(named: "NonStudioTheme") == nil)
        
        // ThemeManager.setting(name:) resolves built-in Studio themes even without a pre-existing file
        let resolved = try ThemeManager.shared.setting(name: cnDark)
        #expect(resolved.background.color != .clear)
    }
    
    
    // MARK: 8. Settings Window Fixed Width Stability
    
    @Test func settingsWindowLocksSizingOptionsToPreventJumping() throws {
        let controller = SidebarSettingsWindowController()
        let window = try #require(controller.window)
        #expect(abs(window.contentLayoutRect.width - 780) <= 2)
        if let hosting = window.contentViewController as? NSHostingController<AnyView> {
            #expect(hosting.sizingOptions.isEmpty)
        }
        window.close()
    }
    
    
    private static func makeKeyEvent(
        char: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: char,
            charactersIgnoringModifiers: char,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
