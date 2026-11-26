//
//  Round41UnifiedPaletteTests.swift
//
//  Tests
//  https://coteditor.com
//

import AppKit
import Foundation
import SwiftUI
import SyntaxFormat
import Testing
@testable import CotEditor

@MainActor
struct Round41UnifiedPaletteTests {
    
    @Test func modernizedAnuraThemesDecodeAndHarmonizeWithStudioPalette() throws {
        let lightURL = try #require(Bundle.main.url(forResource: "Anura", withExtension: "cottheme", subdirectory: "Themes"))
        let darkURL = try #require(Bundle.main.url(forResource: "Anura (Dark)", withExtension: "cottheme", subdirectory: "Themes"))
        
        let decoder = JSONDecoder()
        let anuraLight = try decoder.decode(Theme.self, from: Data(contentsOf: lightURL))
        let anuraDark = try decoder.decode(Theme.self, from: Data(contentsOf: darkURL))
        
        #expect(!anuraLight.isDarkTheme)
        #expect(anuraDark.isDarkTheme)
        #expect(StudioPaletteManager.hexString(from: anuraLight.background.color) == "#FAFAFB")
        #expect(StudioPaletteManager.hexString(from: anuraLight.highlight.color) == "#2F7CF6")
        #expect(StudioPaletteManager.hexString(from: anuraDark.background.color) == "#17181B")
        #expect(StudioPaletteManager.hexString(from: anuraDark.highlight.color) == "#519AFD")
        
        for type in SyntaxType.allCases {
            let lightStyle = try #require(anuraLight.style(for: type))
            let darkStyle = try #require(anuraDark.style(for: type))
            #expect(lightStyle.color.hueComponent > 0)
            #expect(darkStyle.color.hueComponent > 0)
        }
    }
    
    
    @Test func themeAwareTokensAndChromeSyncWithAnuraInsteadOfHardcodedGreen() throws {
        let lightURL = try #require(Bundle.main.url(forResource: "Anura", withExtension: "cottheme", subdirectory: "Themes"))
        let darkURL = try #require(Bundle.main.url(forResource: "Anura (Dark)", withExtension: "cottheme", subdirectory: "Themes"))
        let decoder = JSONDecoder()
        let anuraLight = try decoder.decode(Theme.self, from: Data(contentsOf: lightURL))
        let anuraDark = try decoder.decode(Theme.self, from: Data(contentsOf: darkURL))
        
        let manager = StudioPaletteManager.shared
        let lightTokens = manager.tokens(for: anuraLight, themeName: "Anura", isDark: false)
        let darkTokens = manager.tokens(for: anuraDark, themeName: "Anura (Dark)", isDark: true)
        
        #expect(StudioPaletteManager.hexString(from: NSColor(lightTokens.canvasTop)) == "#FAFAFB")
        #expect(StudioPaletteManager.hexString(from: NSColor(lightTokens.accent)) == "#2F7CF6")
        #expect(StudioPaletteManager.hexString(from: NSColor(darkTokens.canvasTop)) == "#17181B")
        #expect(StudioPaletteManager.hexString(from: NSColor(darkTokens.accent)) == "#519AFD")
        
        // Neutral hairlineStrong never turns colored
        let lightHairlineSat = NSColor(lightTokens.hairlineStrong).usingColorSpace(.sRGB)?.saturationComponent ?? 0
        let darkHairlineSat = NSColor(darkTokens.hairlineStrong).usingColorSpace(.sRGB)?.saturationComponent ?? 0
        #expect(lightHairlineSat < 0.08)
        #expect(darkHairlineSat < 0.08)
        
        // Studio theme names resolve cleanly to their preset triad
        let uvTokens = manager.tokens(for: nil, themeName: "Studio · Ultra Violet (Dark)", isDark: true)
        #expect(StudioPaletteManager.hexString(from: NSColor(uvTokens.accent)) == "#715CB2")
        
        // Chrome palette adopts Anura highlight and distinguishes active tab from strip
        let lightChrome = manager.chromePalette(for: anuraLight, isDark: false)
        let darkChrome = manager.chromePalette(for: anuraDark, isDark: true)
        #expect(!lightChrome.isDark && darkChrome.isDark)
        #expect(lightChrome.activeTabFill != lightChrome.tabBarBackground)
        #expect(darkChrome.activeTabFill != darkChrome.tabBarBackground)
        let lightChromeHue = lightChrome.accent.usingColorSpace(.sRGB)?.hueComponent ?? 0
        let anuraBlueHue = anuraLight.highlight.color.usingColorSpace(.sRGB)?.hueComponent ?? 0
        #expect(abs(lightChromeHue - anuraBlueHue) < 0.03)
    }
    
    
    @Test func boardsMountCleanlyWithThemeDerivedSurfaceAndTokens() throws {
        let lightURL = try #require(Bundle.main.url(forResource: "Anura", withExtension: "cottheme", subdirectory: "Themes"))
        let anuraLight = try JSONDecoder().decode(Theme.self, from: Data(contentsOf: lightURL))
        let tokens = StudioPaletteManager.shared.tokens(for: anuraLight, themeName: "Anura", isDark: false)
        let surface = Color(nsColor: anuraLight.background.color)
        
        let news = DashboardNewsCenterView(
            newsService: .shared,
            tokens: tokens,
            surfaceColor: surface,
            initialSelectedID: nil,
            isEmbeddedInPane: true,
            onClose: { }
        )
        try self.assertMountsAtFullBounds(news)
        
        let marketState = PaneBoardState(kind: .market)
        let market = MarketBoardView(
            boardState: .constant(marketState),
            tokens: tokens,
            surfaceColor: surface
        )
        try self.assertMountsAtFullBounds(market)
        
        let podcastState = PaneBoardState(kind: .podcast)
        let podcast = PodcastBoardView(
            boardState: .constant(podcastState),
            tokens: tokens,
            surfaceColor: surface
        )
        try self.assertMountsAtFullBounds(podcast)
    }
    
    
    private func assertMountsAtFullBounds<V: View>(_ rootView: V) throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        
        let host = NSHostingController(rootView: rootView)
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1120, height: 720))
        
        let contentView = try #require(window.contentView)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        contentView.layoutSubtreeIfNeeded()
        
        #expect(abs(contentView.bounds.width - 1120) <= 2)
        #expect(abs(contentView.bounds.height - 720) <= 2)
    }
    
    
    @Test func softPreviewColorsEliminatePitchBlackAndStayAiryAcrossAllPalettes() {
        let manager = StudioPaletteManager.shared
        for preset in StudioPaletteID.allCases {
            let lightPreview = manager.softPreviewColors(for: preset, isDark: false)
            let darkPreview = manager.softPreviewColors(for: preset, isDark: true)
            
            // Light mode preview surfaces must remain luminous and airy (no harsh dark blocks)
            #expect(lightPreview.canvasLuminance >= 0.85)
            // Dark mode preview surfaces must be lifted into Apple-style soft graphite (not pitch-black)
            #expect(darkPreview.canvasLuminance >= 0.11)
            #expect(darkPreview.canvasLuminance <= 0.25)
        }
    }
}
