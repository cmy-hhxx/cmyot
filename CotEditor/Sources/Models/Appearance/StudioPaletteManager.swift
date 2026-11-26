//
//  StudioPaletteManager.swift
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
import SwiftUI
import Defaults

/// 10 curated global Light/Dark paired color systems covering editor canvas, syntax, sidebar,
/// tab chrome, analytics heatmap, and dashboard cards as one unified design language.
nonisolated enum StudioPaletteID: String, CaseIterable, Identifiable, Codable, Sendable {
    
    case pineCeladon
    case ultraViolet
    case signalCrimson
    case matchaParchment
    case oceanCobalt
    case amberEspresso
    case sakuraQuartz
    case nordFrost
    case terracottaClay
    case graphiteMono
    
    var id: String { self.rawValue }
    
    
    static func resolve(rawValue: String) -> StudioPaletteID {
        if let direct = StudioPaletteID(rawValue: rawValue) {
            return direct
        }
        return .pineCeladon
    }
    
    
    var displayName: String {
        switch self {
            case .pineCeladon: AppLanguage.text("松烟青玉", en: "Pine Celadon")
            case .ultraViolet: AppLanguage.text("电光紫罗兰", en: "Ultra Violet")
            case .signalCrimson: AppLanguage.text("信号绯红", en: "Signal Crimson")
            case .matchaParchment: AppLanguage.text("抹茶手稿", en: "Matcha Marker")
            case .oceanCobalt: AppLanguage.text("沧海钴蓝", en: "Ocean Cobalt")
            case .amberEspresso: AppLanguage.text("琥珀浓缩", en: "Amber Espresso")
            case .sakuraQuartz: AppLanguage.text("樱雾石英", en: "Sakura Quartz")
            case .nordFrost: AppLanguage.text("北欧霜雪", en: "Nord Frost")
            case .terracottaClay: AppLanguage.text("赤陶暖泥", en: "Terracotta Clay")
            case .graphiteMono: AppLanguage.text("石墨极简", en: "Graphite Mono")
        }
    }
    
    
    var canonicalEnglishName: String {
        switch self {
            case .pineCeladon: "Pine Celadon"
            case .ultraViolet: "Ultra Violet"
            case .signalCrimson: "Signal Crimson"
            case .matchaParchment: "Matcha Marker"
            case .oceanCobalt: "Ocean Cobalt"
            case .amberEspresso: "Amber Espresso"
            case .sakuraQuartz: "Sakura Quartz"
            case .nordFrost: "Nord Frost"
            case .terracottaClay: "Terracotta Clay"
            case .graphiteMono: "Graphite Mono"
        }
    }
    
    
    var subtitle: String {
        switch self {
            case .pineCeladon: "XUAN · PINE INK · CELADON"
            case .ultraViolet: "MIDNIGHT · SILVER · ULTRA VIOLET"
            case .signalCrimson: "CLOUD · CARBON · CRIMSON"
            case .matchaParchment: "PARCHMENT · INK · MATCHA"
            case .oceanCobalt: "ICE SLATE · PRUSSIAN · COBALT"
            case .amberEspresso: "LATTE · ESPRESSO · AMBER"
            case .sakuraQuartz: "PETAL · PLUM · SAKURA"
            case .nordFrost: "FROST · POLAR · ARCTIC"
            case .terracottaClay: "LINEN · OBSIDIAN · CLAY"
            case .graphiteMono: "PAPER · GRAPHITE · SLATE"
        }
    }
}


/// The 3 swatch building blocks (`01`, `02`, `03`) of any designer color system.
nonisolated struct StudioPaletteTriad: Equatable, Sendable {
    
    let lightPaperHex: String
    let lightPaperName: String
    let darkInkHex: String
    let darkInkName: String
    let accentHex: String
    let accentName: String
}


/// Resolved light- or dark-mode color tokens computed from a designer triad for Dashboard, Hubs, and Chrome.
struct StudioColorTokens: Equatable, Sendable {
    
    let isDark: Bool
    let canvasTop: Color
    let canvasBottom: Color
    let mistAccent: Color
    let card: Color
    let cardShadow: Color
    let inset: Color
    let insetHover: Color
    let hairline: Color
    let hairlineStrong: Color
    let topSpecular: Color
    let architecturalDot: Color
    let primaryInk: Color
    let accent: Color
    let accentText: Color
    let onAccentInk: Color
    let secondaryAccent: Color
    let paleAccent: Color
    let emptyDot: Color
    let positivePillBg: Color
    let neutralPillBg: Color
    let heat1: Color
    let heat2: Color
    let heat3: Color
    let heat4: Color
}


/// Soft, eye-friendly preview colors derived from a `StudioPaletteID` for the Settings Appearance pane,
/// avoiding harsh pitch-black blocks in Light mode and lifting near-black voids into Apple-style graphite in Dark mode.
struct StudioPalettePreviewColors: Equatable, Sendable {
    
    let canvas: Color
    let sidebar: Color
    let accent: Color
    let swatch: Color
    let linePrimary: Color
    let lineSecondary: Color
    let ambientWash: Color
    let canvasLuminance: Double
}


/// Harmonized window chrome colors (titlebar, tab bar, status bar, toolbar pills) derived
/// from the active editor `Theme` and the user's `StudioPaletteManager` accent triad.
struct WindowChromePalette: Equatable, Sendable {
    
    let isDark: Bool
    let titlebarBackground: NSColor
    let tabBarBackground: NSColor
    let tabBarSeparator: NSColor
    let activeTabFill: NSColor
    let activeTabBorder: NSColor
    let hoveredTabFill: NSColor
    let activeTabText: NSColor
    let inactiveTabText: NSColor
    let accent: NSColor
    let statusBarBackground: NSColor
    let statusBarSeparator: NSColor
    let statusBarText: NSColor
    let toolbarPillFill: NSColor
    let toolbarPillHoverFill: NSColor
    let toolbarPillText: NSColor
}


@MainActor @Observable
final class StudioPaletteManager {
    
    static let shared = StudioPaletteManager()
    static let paletteDidChangeNotification = Notification.Name("StudioPaletteManagerDidChange")
    
    var selectedID: StudioPaletteID {
        didSet {
            guard self.selectedID != oldValue else { return }
            self.database.set(self.selectedID.rawValue, forKey: CotLocalDatabase.ConfigKey.studioPaletteID)
            self.postPaletteChange()
        }
    }
    
    /// Incremented monotonically whenever active tokens change, making SwiftUI observation explicit.
    private(set) var revision: Int = 0
    
    private let database: CotLocalDatabase
    @ObservationIgnored private var cachedTokensRevision: Int = -1
    @ObservationIgnored private var cachedTokensByKey: [String: StudioColorTokens] = [:]
    @ObservationIgnored private var cachedChromeEntry: (revision: Int, theme: Theme?, isDark: Bool, palette: WindowChromePalette)?
    
    
    init(database: CotLocalDatabase = .shared) {
        self.database = database
        let rawID = database.string(
            forKey: CotLocalDatabase.ConfigKey.studioPaletteID,
            default: StudioPaletteID.pineCeladon.rawValue
        )
        self.selectedID = StudioPaletteID.resolve(rawValue: rawID)
    }
    
    
    /// Reloads palette selection from the backing database (e.g. after DB import or profile switch).
    func reloadFromDatabase() {
        let rawID = self.database.string(
            forKey: CotLocalDatabase.ConfigKey.studioPaletteID,
            default: StudioPaletteID.pineCeladon.rawValue
        )
        self.selectedID = StudioPaletteID.resolve(rawValue: rawID)
        self.postPaletteChange()
    }
    
    
    private func postPaletteChange() {
        self.revision &+= 1
        NotificationCenter.default.post(name: Self.paletteDidChangeNotification, object: self)
    }
    
    
    func selectPalette(_ id: StudioPaletteID, syncEditorTheme: Bool = false) {
        self.selectedID = id
        if syncEditorTheme {
            self.syncEditorThemeWithCurrentAppearance()
        }
    }
    
    
    /// Resolves whether the current appearance mode evaluates to Dark mode.
    static func resolvedIsDark(for mode: AppearanceMode = UserDefaults.standard[.documentAppearance]) -> Bool {
        switch mode {
            case .light: false
            case .dark: true
            case .default:
                NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }
    
    
    /// Canonical paired theme name for `(paletteID, preferDark)` used by `ThemeManager`.
    nonisolated static func themeName(for paletteID: StudioPaletteID, preferDark: Bool) -> String {
        "Studio · \(paletteID.canonicalEnglishName) (\(preferDark ? "Dark" : "Light"))"
    }
    
    
    /// Switches Light / Dark / System appearance while keeping the EXACT SAME active palette
    /// across editor, sidebar, tab chrome, heatmap, and cards.
    func applyAppearanceMode(_ mode: AppearanceMode) {
        let preferDark = Self.resolvedIsDark(for: mode)
        UserDefaults.standard[.pinsThemeAppearance] = false
        UserDefaults.standard[.documentAppearance] = mode
        self.applyPaletteToEditorTheme(preferDark: preferDark, updateDocumentAppearance: false)
        CotLocalDatabase.shared.syncUserPreferencesToDatabase()
        self.postPaletteChange()
    }
    
    
    /// Ensures the active editor theme always matches `selectedID` + the current Light/Dark appearance.
    func syncEditorThemeWithCurrentAppearance() {
        let preferDark = Self.resolvedIsDark()
        self.applyPaletteToEditorTheme(preferDark: preferDark, updateDocumentAppearance: false)
    }
    
    
    func triad(for id: StudioPaletteID? = nil) -> StudioPaletteTriad {
        let resolvedID = id ?? self.selectedID
        switch resolvedID {
            case .pineCeladon:
                return StudioPaletteTriad(
                    lightPaperHex: "#F2F3EF",
                    lightPaperName: AppLanguage.text("宣纸素白", en: "Xuan Paper"),
                    darkInkHex: "#111413",
                    darkInkName: AppLanguage.text("松烟墨黑", en: "Pine Ink"),
                    accentHex: "#2E8B67",
                    accentName: AppLanguage.text("青玉松翠", en: "Celadon Pine")
                )
            case .ultraViolet:
                return StudioPaletteTriad(
                    lightPaperHex: "#E7E7E7",
                    lightPaperName: AppLanguage.text("银月冷白", en: "Silver Mist"),
                    darkInkHex: "#0E0E16",
                    darkInkName: AppLanguage.text("午夜深黑", en: "Midnight Black"),
                    accentHex: "#715CB2",
                    accentName: AppLanguage.text("电光紫罗兰", en: "Ultra Violet")
                )
            case .signalCrimson:
                return StudioPaletteTriad(
                    lightPaperHex: "#EAEAEA",
                    lightPaperName: AppLanguage.text("冷感纸白", en: "Cloud Dancer"),
                    darkInkHex: "#111111",
                    darkInkName: AppLanguage.text("科技碳黑", en: "Jet Carbon"),
                    accentHex: "#D53740",
                    accentName: AppLanguage.text("信号绯红", en: "Signal Crimson")
                )
            case .matchaParchment:
                return StudioPaletteTriad(
                    lightPaperHex: "#E7DBB8",
                    lightPaperName: AppLanguage.text("羊皮纸米", en: "Parchment Cream"),
                    darkInkHex: "#121212",
                    darkInkName: AppLanguage.text("书卷浓黑", en: "Bookbind Ink"),
                    accentHex: "#A4CE46",
                    accentName: AppLanguage.text("抹茶荧光绿", en: "Matcha Marker")
                )
            case .oceanCobalt:
                return StudioPaletteTriad(
                    lightPaperHex: "#EDF3FA",
                    lightPaperName: AppLanguage.text("冰岩淡蓝", en: "Ice Slate"),
                    darkInkHex: "#0D1524",
                    darkInkName: AppLanguage.text("深海普鲁士", en: "Prussian Navy"),
                    accentHex: "#2272DC",
                    accentName: AppLanguage.text("沧海钴蓝", en: "Ocean Cobalt")
                )
            case .amberEspresso:
                return StudioPaletteTriad(
                    lightPaperHex: "#F5EFE6",
                    lightPaperName: AppLanguage.text("拿铁暖纸", en: "Latte Ivory"),
                    darkInkHex: "#16120F",
                    darkInkName: AppLanguage.text("浓缩深烘", en: "Espresso Roast"),
                    accentHex: "#D47E1E",
                    accentName: AppLanguage.text("琥珀焦糖", en: "Warm Amber")
                )
            case .sakuraQuartz:
                return StudioPaletteTriad(
                    lightPaperHex: "#F6EEF1",
                    lightPaperName: AppLanguage.text("樱雾粉白", en: "Petal White"),
                    darkInkHex: "#171115",
                    darkInkName: AppLanguage.text("暮梅炭黑", en: "Plum Charcoal"),
                    accentHex: "#D44E7A",
                    accentName: AppLanguage.text("石英樱红", en: "Sakura Quartz")
                )
            case .nordFrost:
                return StudioPaletteTriad(
                    lightPaperHex: "#EDF2F7",
                    lightPaperName: AppLanguage.text("北国霜纸", en: "Frost Paper"),
                    darkInkHex: "#121821",
                    darkInkName: AppLanguage.text("极夜蓝炭", en: "Polar Night"),
                    accentHex: "#3D8FB3",
                    accentName: AppLanguage.text("冰川青蓝", en: "Arctic Cyan")
                )
            case .terracottaClay:
                return StudioPaletteTriad(
                    lightPaperHex: "#F4ECE4",
                    lightPaperName: AppLanguage.text("亚麻暖砂", en: "Sand Linen"),
                    darkInkHex: "#171210",
                    darkInkName: AppLanguage.text("玄陶深棕", en: "Obsidian Clay"),
                    accentHex: "#C85A38",
                    accentName: AppLanguage.text("赤陶暖锈", en: "Terracotta")
                )
            case .graphiteMono:
                return StudioPaletteTriad(
                    lightPaperHex: "#F0F0F2",
                    lightPaperName: AppLanguage.text("画室素灰", en: "Studio Paper"),
                    darkInkHex: "#121214",
                    darkInkName: AppLanguage.text("建筑石墨", en: "Graphite Ink"),
                    accentHex: "#525966",
                    accentName: AppLanguage.text("极简岩灰", en: "Architectural Slate")
                )
        }
    }
    
    
    var activeAccentColor: Color {
        let _ = self.revision
        return Self.swiftUIColor(hex: self.triad().accentHex)
    }
    
    
    var activeNSAccentColor: NSColor {
        let _ = self.revision
        return Self.nsColor(hex: self.triad().accentHex)
    }
    
    
    func tokens(isDark: Bool, id: StudioPaletteID? = nil) -> StudioColorTokens {
        let rev = self.revision
        if self.cachedTokensRevision != rev {
            self.cachedTokensRevision = rev
            self.cachedTokensByKey.removeAll(keepingCapacity: true)
        }
        let resolvedID = id ?? self.selectedID
        let cacheKey = "\(resolvedID.rawValue)|\(isDark)"
        if let hit = self.cachedTokensByKey[cacheKey] {
            return hit
        }
        let triad = self.triad(for: resolvedID)
        let lightPaperNS = Self.nsColor(hex: triad.lightPaperHex)
        let darkInkNS = Self.nsColor(hex: triad.darkInkHex)
        let accentNS = Self.nsColor(hex: triad.accentHex)
        let isMatcha = (resolvedID == .matchaParchment)
        
        let built: StudioColorTokens = if isDark {
            Self.buildTokens(
                isDark: true,
                canvasTopNS: darkInkNS,
                canvasBottomNS: Self.blend(darkInkNS, with: .white, ratio: 0.03),
                cardNS: Self.blend(darkInkNS, with: .white, ratio: 0.06),
                insetNS: Self.blend(darkInkNS, with: .white, ratio: 0.11),
                insetHoverNS: Self.blend(darkInkNS, with: .white, ratio: 0.16),
                emptyDotNS: Self.blend(darkInkNS, with: .white, ratio: 0.12),
                primaryInkNS: lightPaperNS,
                accentNS: accentNS
            )
        } else {
            Self.buildTokens(
                isDark: false,
                canvasTopNS: isMatcha ? Self.blend(lightPaperNS, with: .white, ratio: 0.14) : lightPaperNS,
                canvasBottomNS: isMatcha ? lightPaperNS : Self.blend(lightPaperNS, with: .white, ratio: 0.35),
                cardNS: isMatcha ? Self.blend(lightPaperNS, with: .white, ratio: 0.62) : Self.blend(lightPaperNS, with: .white, ratio: 0.82),
                insetNS: Self.blend(lightPaperNS, with: darkInkNS, ratio: 0.055),
                insetHoverNS: Self.blend(lightPaperNS, with: darkInkNS, ratio: 0.105),
                emptyDotNS: Self.blend(lightPaperNS, with: darkInkNS, ratio: 0.10),
                primaryInkNS: darkInkNS,
                accentNS: accentNS,
                isMatcha: isMatcha
            )
        }
        self.cachedTokensByKey[cacheKey] = built
        return built
    }
    
    
    /// Derives cohesive surface, ink, hairline, and accent tokens synchronized with any active editor `Theme`.
    func tokens(for theme: Theme?, themeName: String? = nil, isDark: Bool) -> StudioColorTokens {
        if let themeName, let parsed = Self.parseStudioThemeName(themeName) {
            return self.tokens(isDark: isDark, id: parsed.paletteID)
        }
        guard let theme else {
            return self.tokens(isDark: isDark)
        }
        
        let editorBg = theme.background.color.usingColorSpace(.sRGB) ?? theme.background.color
        let themeText = theme.text.color.usingColorSpace(.sRGB) ?? theme.text.color
        let isThemeDark = theme.isDarkTheme
        
        let rawAccent: NSColor = if !theme.highlight.usesSystemSetting {
            theme.highlight.color.usingColorSpace(.sRGB) ?? theme.highlight.color
        } else {
            Self.nsColor(hex: isThemeDark ? "#519AFD" : "#2F7CF6")
        }
        let accentNS = Self.saturation(of: rawAccent) >= 0.08
            ? rawAccent
            : Self.nsColor(hex: isThemeDark ? "#519AFD" : "#2F7CF6")
        
        if isThemeDark {
            return Self.buildTokens(
                isDark: true,
                canvasTopNS: editorBg,
                canvasBottomNS: Self.blend(editorBg, with: .white, ratio: 0.022),
                cardNS: Self.blend(editorBg, with: .white, ratio: 0.048),
                insetNS: Self.blend(editorBg, with: .white, ratio: 0.082),
                insetHoverNS: Self.blend(editorBg, with: .white, ratio: 0.125),
                emptyDotNS: Self.blend(editorBg, with: .white, ratio: 0.11),
                primaryInkNS: themeText,
                accentNS: accentNS
            )
        } else {
            return Self.buildTokens(
                isDark: false,
                canvasTopNS: editorBg,
                canvasBottomNS: Self.blend(editorBg, with: themeText, ratio: 0.022),
                cardNS: Self.blend(editorBg, with: .white, ratio: 0.88),
                insetNS: Self.blend(editorBg, with: themeText, ratio: 0.045),
                insetHoverNS: Self.blend(editorBg, with: themeText, ratio: 0.085),
                emptyDotNS: Self.blend(editorBg, with: themeText, ratio: 0.09),
                primaryInkNS: themeText,
                accentNS: accentNS
            )
        }
    }
    
    
    private static func buildTokens(
        isDark: Bool,
        canvasTopNS: NSColor,
        canvasBottomNS: NSColor,
        cardNS: NSColor,
        insetNS: NSColor,
        insetHoverNS: NSColor,
        emptyDotNS: NSColor,
        primaryInkNS: NSColor,
        accentNS: NSColor,
        isMatcha: Bool = false
    ) -> StudioColorTokens {
        if isDark {
            let liftedAccentNS = Self.ensureDarkModeVisibility(accentNS)
            let secondaryAccentNS = Self.blend(liftedAccentNS, with: canvasTopNS, ratio: 0.30)
            let paleAccentNS = Self.blend(liftedAccentNS, with: canvasTopNS, ratio: 0.65)
            let onAccentInkNS = Self.relativeLuminance(accentNS) > 0.50
                ? Self.nsColor(hex: "#121212")
                : NSColor.white
            
            return StudioColorTokens(
                isDark: true,
                canvasTop: Color(nsColor: canvasTopNS),
                canvasBottom: Color(nsColor: canvasBottomNS),
                mistAccent: Color(nsColor: liftedAccentNS).opacity(0.14),
                card: Color(nsColor: cardNS),
                cardShadow: Color.black.opacity(0.32),
                inset: Color(nsColor: insetNS),
                insetHover: Color(nsColor: insetHoverNS),
                hairline: Color.white.opacity(0.085),
                hairlineStrong: Color.white.opacity(0.17),
                topSpecular: Color.white.opacity(0.07),
                architecturalDot: Color.white.opacity(0.045),
                primaryInk: Color(nsColor: primaryInkNS),
                accent: Color(nsColor: accentNS),
                accentText: Color(nsColor: liftedAccentNS),
                onAccentInk: Color(nsColor: onAccentInkNS),
                secondaryAccent: Color(nsColor: secondaryAccentNS),
                paleAccent: Color(nsColor: paleAccentNS),
                emptyDot: Color(nsColor: emptyDotNS),
                positivePillBg: Color(nsColor: accentNS).opacity(0.18),
                neutralPillBg: Color.white.opacity(0.08),
                heat1: Color(nsColor: Self.blend(canvasTopNS, with: liftedAccentNS, ratio: 0.24)),
                heat2: Color(nsColor: Self.blend(canvasTopNS, with: liftedAccentNS, ratio: 0.45)),
                heat3: Color(nsColor: Self.blend(canvasTopNS, with: liftedAccentNS, ratio: 0.72)),
                heat4: Color(nsColor: liftedAccentNS)
            )
        } else {
            let readableAccentTextNS = Self.ensureLightModeTextContrast(accentNS, against: cardNS)
            let secondaryAccentNS = Self.blend(accentNS, with: canvasTopNS, ratio: 0.36)
            let paleAccentNS = Self.blend(accentNS, with: canvasTopNS, ratio: 0.72)
            let onAccentInkNS = Self.relativeLuminance(accentNS) > 0.48
                ? primaryInkNS
                : NSColor.white
            
            return StudioColorTokens(
                isDark: false,
                canvasTop: Color(nsColor: canvasTopNS),
                canvasBottom: Color(nsColor: canvasBottomNS),
                mistAccent: Color(nsColor: accentNS).opacity(0.12),
                card: Color(nsColor: cardNS),
                cardShadow: Color.black.opacity(0.055),
                inset: Color(nsColor: insetNS),
                insetHover: Color(nsColor: insetHoverNS),
                hairline: Color.black.opacity(0.08),
                hairlineStrong: Color.black.opacity(0.16),
                topSpecular: Color.white.opacity(0.78),
                architecturalDot: Color.black.opacity(0.045),
                primaryInk: Color(nsColor: primaryInkNS),
                accent: Color(nsColor: accentNS),
                accentText: Color(nsColor: readableAccentTextNS),
                onAccentInk: Color(nsColor: onAccentInkNS),
                secondaryAccent: Color(nsColor: secondaryAccentNS),
                paleAccent: Color(nsColor: paleAccentNS),
                emptyDot: Color(nsColor: emptyDotNS),
                positivePillBg: Color(nsColor: accentNS).opacity(isMatcha ? 0.28 : 0.12),
                neutralPillBg: Color(nsColor: primaryInkNS).opacity(0.055),
                heat1: Color(nsColor: Self.blend(canvasTopNS, with: accentNS, ratio: 0.28)),
                heat2: Color(nsColor: Self.blend(canvasTopNS, with: accentNS, ratio: 0.52)),
                heat3: Color(nsColor: Self.blend(canvasTopNS, with: accentNS, ratio: 0.76)),
                heat4: Color(nsColor: accentNS)
            )
        }
    }
    
    
    /// Builds a software-bundled `Theme` from a `StudioPaletteID` and dark/light preference.
    func buildTheme(for paletteID: StudioPaletteID, preferDark: Bool) -> Theme {
        let triad = self.triad(for: paletteID)
        let lightPaper = Self.nsColor(hex: triad.lightPaperHex)
        let darkInk = Self.nsColor(hex: triad.darkInkHex)
        let accent = Self.nsColor(hex: triad.accentHex)
        
        var theme = Theme()
        if preferDark {
            theme.background = .init(color: darkInk)
            theme.text = .init(color: lightPaper)
            theme.lineHighlight = .init(color: Self.blend(darkInk, with: .white, ratio: 0.055))
            theme.invisibles = .init(color: lightPaper.withAlphaComponent(0.28))
            theme.selection = .init(color: accent.withAlphaComponent(0.32), usesSystemSetting: false)
            theme.insertionPoint = .init(color: Self.ensureDarkModeVisibility(accent), usesSystemSetting: false)
            theme.highlight = .init(color: accent, usesSystemSetting: false)
            theme.keywords = .init(color: Self.ensureDarkModeVisibility(accent))
            theme.commands = .init(color: Self.blend(Self.ensureDarkModeVisibility(accent), with: lightPaper, ratio: 0.28))
            theme.types = .init(color: Self.blend(lightPaper, with: Self.ensureDarkModeVisibility(accent), ratio: 0.42))
            theme.attributes = .init(color: Self.blend(lightPaper, with: Self.ensureDarkModeVisibility(accent), ratio: 0.55))
            theme.variables = .init(color: Self.blend(lightPaper, with: .white, ratio: 0.15))
            theme.values = .init(color: Self.ensureDarkModeVisibility(accent))
            theme.numbers = .init(color: Self.blend(Self.ensureDarkModeVisibility(accent), with: .white, ratio: 0.35))
            theme.strings = .init(color: Self.blend(lightPaper, with: Self.ensureDarkModeVisibility(accent), ratio: 0.30))
            theme.characters = .init(color: Self.ensureDarkModeVisibility(accent))
            theme.comments = .init(color: lightPaper.withAlphaComponent(0.45))
        } else {
            let softPaper = (paletteID == .matchaParchment) ? lightPaper : Self.blend(lightPaper, with: .white, ratio: 0.52)
            let crispAccent = Self.ensureLightModeTextContrast(accent, against: softPaper)
            theme.background = .init(color: softPaper)
            theme.text = .init(color: darkInk)
            theme.lineHighlight = .init(color: Self.blend(softPaper, with: darkInk, ratio: 0.045))
            theme.invisibles = .init(color: darkInk.withAlphaComponent(0.26))
            theme.selection = .init(color: accent.withAlphaComponent(0.26), usesSystemSetting: false)
            theme.insertionPoint = .init(color: accent, usesSystemSetting: false)
            theme.highlight = .init(color: accent, usesSystemSetting: false)
            theme.keywords = .init(color: crispAccent)
            theme.commands = .init(color: Self.blend(crispAccent, with: darkInk, ratio: 0.25))
            theme.types = .init(color: Self.blend(darkInk, with: crispAccent, ratio: 0.45))
            theme.attributes = .init(color: Self.blend(darkInk, with: crispAccent, ratio: 0.60))
            theme.variables = .init(color: Self.blend(darkInk, with: .black, ratio: 0.10))
            theme.values = .init(color: crispAccent)
            theme.numbers = .init(color: Self.blend(crispAccent, with: darkInk, ratio: 0.20))
            theme.strings = .init(color: Self.blend(darkInk, with: crispAccent, ratio: 0.35))
            theme.characters = .init(color: crispAccent)
            theme.comments = .init(color: darkInk.withAlphaComponent(0.44))
        }
        return theme
    }
    
    
    /// Parses a `Studio · ...` theme name into its `(paletteID, preferDark)` pair, recognizing both
    /// canonical English names and legacy Chinese/English saved names.
    nonisolated static func parseStudioThemeName(_ name: String) -> (paletteID: StudioPaletteID, preferDark: Bool)? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("Studio · ") else { return nil }
        let body = String(trimmed.dropFirst("Studio · ".count))
        
        let preferDark: Bool
        let baseTitle: String
        if body.hasSuffix(" (暗色)") {
            preferDark = true
            baseTitle = String(body.dropLast(" (暗色)".count))
        } else if body.hasSuffix(" (Dark)") {
            preferDark = true
            baseTitle = String(body.dropLast(" (Dark)".count))
        } else if body.hasSuffix(" (浅色)") {
            preferDark = false
            baseTitle = String(body.dropLast(" (浅色)".count))
        } else if body.hasSuffix(" (Light)") {
            preferDark = false
            baseTitle = String(body.dropLast(" (Light)".count))
        } else {
            preferDark = false
            baseTitle = body
        }
        
        let matchedID: StudioPaletteID? = switch baseTitle {
            case "松烟青玉", "Pine Celadon": .pineCeladon
            case "电光紫罗兰", "Ultra Violet": .ultraViolet
            case "信号绯红", "Signal Crimson": .signalCrimson
            case "抹茶荧光绿", "抹茶手稿", "Matcha Marker": .matchaParchment
            case "沧海钴蓝", "Ocean Cobalt": .oceanCobalt
            case "琥珀浓缩", "Amber Espresso": .amberEspresso
            case "樱雾石英", "Sakura Quartz": .sakuraQuartz
            case "北欧霜雪", "Nord Frost": .nordFrost
            case "赤陶暖泥", "Terracotta Clay": .terracottaClay
            case "石墨极简", "Graphite Mono": .graphiteMono
            case "自定义三色", "Custom Triad": .pineCeladon
            default: StudioPaletteID(rawValue: baseTitle)
        }
        guard let matchedID else { return nil }
        return (matchedID, preferDark)
    }
    
    
    /// Synthesizes any built-in `Studio · ...` editor theme by name (Chinese or English) so migrating
    /// a database to another machine never fails with a missing theme resource error.
    func synthesizedTheme(named name: String) -> Theme? {
        guard let parsed = Self.parseStudioThemeName(name) else { return nil }
        return self.buildTheme(for: parsed.paletteID, preferDark: parsed.preferDark)
    }
    
    
    /// Creates or updates both the Light and Dark paired `Theme` files for the active `StudioPaletteID`
    /// and activates the requested `preferDark` variant without breaking appearance mode coupling.
    func applyPaletteToEditorTheme(preferDark: Bool, updateDocumentAppearance: Bool = true) {
        let lightName = Self.themeName(for: self.selectedID, preferDark: false)
        let darkName = Self.themeName(for: self.selectedID, preferDark: true)
        let lightTheme = self.buildTheme(for: self.selectedID, preferDark: false)
        let darkTheme = self.buildTheme(for: self.selectedID, preferDark: true)
        
        if !ThemeManager.shared.settingNames.contains(lightName) || (try? ThemeManager.shared.setting(name: lightName)) != lightTheme {
            try? ThemeManager.shared.save(setting: lightTheme, name: lightName)
        }
        if !ThemeManager.shared.settingNames.contains(darkName) || (try? ThemeManager.shared.setting(name: darkName)) != darkTheme {
            try? ThemeManager.shared.save(setting: darkTheme, name: darkName)
        }
        
        UserDefaults.standard[.theme] = preferDark ? darkName : lightName
        UserDefaults.standard[.pinsThemeAppearance] = false
        if updateDocumentAppearance {
            UserDefaults.standard[.documentAppearance] = preferDark ? AppearanceMode.dark : AppearanceMode.light
        }
    }
    
    
    /// Syncs the active editor theme with the current Studio Palette, preserving current Light/Dark mode.
    func syncActiveEditorTheme(preferDark: Bool, applyIfNonStudio: Bool = true) {
        let resolvedDark = Self.resolvedIsDark()
        if applyIfNonStudio || UserDefaults.standard[.theme].hasPrefix("Studio · ") {
            self.applyPaletteToEditorTheme(preferDark: resolvedDark, updateDocumentAppearance: false)
        } else {
            self.applyPaletteToEditorTheme(preferDark: preferDark, updateDocumentAppearance: false)
        }
    }
    
    
    /// Resolves a unified, theme-aware window chrome palette so the tab bar, titlebar, status bar,
    /// and toolbar pills harmonize with the active editor theme and Studio Palette without clashing.
    func chromePalette(for theme: Theme?, isDark appearanceIsDark: Bool) -> WindowChromePalette {
        let rev = self.revision
        if let cached = self.cachedChromeEntry,
           cached.revision == rev,
           cached.isDark == appearanceIsDark,
           cached.theme == theme
        {
            return cached.palette
        }
        let triad = self.triad()
        let isDark = theme?.isDarkTheme ?? appearanceIsDark
        
        let fallbackEditorBg: NSColor = isDark
            ? Self.nsColor(hex: triad.darkInkHex)
            : (self.selectedID == .matchaParchment
                ? Self.nsColor(hex: triad.lightPaperHex)
                : Self.blend(Self.nsColor(hex: triad.lightPaperHex), with: .white, ratio: 0.52))
        let fallbackText: NSColor = isDark
            ? Self.nsColor(hex: triad.lightPaperHex)
            : Self.nsColor(hex: triad.darkInkHex)
        
        let editorBg = (theme?.background.color ?? fallbackEditorBg).usingColorSpace(.sRGB)
            ?? (theme?.background.color ?? fallbackEditorBg)
        let themeText = (theme?.text.color ?? fallbackText).usingColorSpace(.sRGB)
            ?? (theme?.text.color ?? fallbackText)
        let rawAccent: NSColor = if let theme, !theme.highlight.usesSystemSetting {
            theme.highlight.color.usingColorSpace(.sRGB) ?? theme.highlight.color
        } else {
            Self.nsColor(hex: triad.accentHex)
        }
        
        let built: WindowChromePalette
        if isDark {
            let bgLum = Self.relativeLuminance(editorBg)
            let tabBarBg = bgLum < 0.05
                ? Self.blend(editorBg, with: .white, ratio: 0.025)
                : Self.blend(editorBg, with: .black, ratio: 0.18)
            let activeTabFill = Self.blend(editorBg, with: .white, ratio: 0.065)
            let activeTabBorder = themeText.withAlphaComponent(0.11)
            let hoveredTabFill = themeText.withAlphaComponent(0.06)
            let separator = themeText.withAlphaComponent(0.09)
            let activeText = themeText.withAlphaComponent(0.95)
            let inactiveText = themeText.withAlphaComponent(0.56)
            let accent = Self.ensureDarkModeVisibility(rawAccent)
            let pillFill = Self.blend(editorBg, with: .white, ratio: 0.12)
            let pillHover = Self.blend(editorBg, with: .white, ratio: 0.18)
            
            built = WindowChromePalette(
                isDark: true,
                titlebarBackground: tabBarBg,
                tabBarBackground: tabBarBg,
                tabBarSeparator: separator,
                activeTabFill: activeTabFill,
                activeTabBorder: activeTabBorder,
                hoveredTabFill: hoveredTabFill,
                activeTabText: activeText,
                inactiveTabText: inactiveText,
                accent: accent,
                statusBarBackground: tabBarBg,
                statusBarSeparator: separator,
                statusBarText: inactiveText,
                toolbarPillFill: pillFill,
                toolbarPillHoverFill: pillHover,
                toolbarPillText: activeText
            )
        } else {
            let tabBarBg = Self.blend(editorBg, with: themeText, ratio: 0.032)
            let activeTabFill = Self.blend(editorBg, with: .white, ratio: 0.85)
            let activeTabBorder = themeText.withAlphaComponent(0.09)
            let hoveredTabFill = themeText.withAlphaComponent(0.05)
            let separator = themeText.withAlphaComponent(0.08)
            let activeText = themeText.withAlphaComponent(0.92)
            let inactiveText = themeText.withAlphaComponent(0.54)
            let accent = Self.ensureLightModeTextContrast(rawAccent, against: activeTabFill)
            let pillFill = Self.blend(editorBg, with: themeText, ratio: 0.07)
            let pillHover = Self.blend(editorBg, with: themeText, ratio: 0.12)
            
            built = WindowChromePalette(
                isDark: false,
                titlebarBackground: tabBarBg,
                tabBarBackground: tabBarBg,
                tabBarSeparator: separator,
                activeTabFill: activeTabFill,
                activeTabBorder: activeTabBorder,
                hoveredTabFill: hoveredTabFill,
                activeTabText: activeText,
                inactiveTabText: inactiveText,
                accent: accent,
                statusBarBackground: tabBarBg,
                statusBarSeparator: separator,
                statusBarText: inactiveText,
                toolbarPillFill: pillFill,
                toolbarPillHoverFill: pillHover,
                toolbarPillText: activeText
            )
        }
        self.cachedChromeEntry = (rev, theme, appearanceIsDark, built)
        return built
    }
    
    
    /// Produces serene, appearance-adaptive preview colors for the Appearance Settings palette cards.
    func softPreviewColors(for id: StudioPaletteID, isDark: Bool) -> StudioPalettePreviewColors {
        let triad = self.triad(for: id)
        let lightPaperNS = Self.nsColor(hex: triad.lightPaperHex)
        let darkInkNS = Self.nsColor(hex: triad.darkInkHex)
        let accentNS = Self.nsColor(hex: triad.accentHex)
        
        if isDark {
            // Lift pitch-black inks (#0D1524 / #111111) toward Apple's warm-neutral dark graphite (#303238)
            // while preserving each palette's signature undertone.
            let appleGraphite = NSColor(srgbRed: 0.196, green: 0.200, blue: 0.220, alpha: 1.0)
            let softCanvasNS = Self.blend(darkInkNS, with: appleGraphite, ratio: 0.48)
            let softSidebarNS = Self.blend(softCanvasNS, with: .white, ratio: 0.065)
            let liftedAccentNS = Self.ensureDarkModeVisibility(accentNS)
            let softAccentNS = Self.blend(liftedAccentNS, with: softCanvasNS, ratio: 0.14)
            
            return StudioPalettePreviewColors(
                canvas: Color(nsColor: softCanvasNS),
                sidebar: Color(nsColor: softSidebarNS),
                accent: Color(nsColor: softAccentNS),
                swatch: Color(nsColor: liftedAccentNS),
                linePrimary: Color.white.opacity(0.22),
                lineSecondary: Color.white.opacity(0.11),
                ambientWash: Color(nsColor: liftedAccentNS).opacity(0.11),
                canvasLuminance: Double(Self.relativeLuminance(softCanvasNS))
            )
        } else {
            // Lift tinted papers smoothly toward luminous stationery white so cards blend effortlessly
            // into macOS Light Mode without heavy gray or yellow blocks.
            let isMatcha = (id == .matchaParchment)
            let softCanvasNS = Self.blend(lightPaperNS, with: .white, ratio: isMatcha ? 0.42 : 0.48)
            let softSidebarNS = Self.blend(lightPaperNS, with: .white, ratio: isMatcha ? 0.24 : 0.22)
            let readableAccentNS = Self.ensureLightModeTextContrast(accentNS, against: softCanvasNS)
            let softBarAccentNS = Self.blend(accentNS, with: softCanvasNS, ratio: 0.16)
            
            return StudioPalettePreviewColors(
                canvas: Color(nsColor: softCanvasNS),
                sidebar: Color(nsColor: softSidebarNS),
                accent: Color(nsColor: softBarAccentNS),
                swatch: Color(nsColor: readableAccentNS),
                linePrimary: Color.black.opacity(0.13),
                lineSecondary: Color.black.opacity(0.075),
                ambientWash: Color(nsColor: accentNS).opacity(0.065),
                canvasLuminance: Double(Self.relativeLuminance(softCanvasNS))
            )
        }
    }
    
    
    // MARK: Color Math Helpers
    
    static func nsColor(hex: String) -> NSColor {
        let raw = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        guard Scanner(string: raw).scanHexInt64(&value), raw.count == 6 else {
            return .controlAccentColor
        }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
    
    
    static func swiftUIColor(hex: String) -> Color {
        Color(nsColor: self.nsColor(hex: hex))
    }
    
    
    static func hexString(from nsColor: NSColor) -> String {
        let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
        let r = Int((max(0, min(1, srgb.redComponent)) * 255).rounded())
        let g = Int((max(0, min(1, srgb.greenComponent)) * 255).rounded())
        let b = Int((max(0, min(1, srgb.blueComponent)) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
    
    
    private static func blend(_ a: NSColor, with b: NSColor, ratio: CGFloat) -> NSColor {
        let t = max(0, min(1, ratio))
        let ca = a.usingColorSpace(.sRGB) ?? a
        let cb = b.usingColorSpace(.sRGB) ?? b
        return NSColor(
            srgbRed: ca.redComponent * (1 - t) + cb.redComponent * t,
            green: ca.greenComponent * (1 - t) + cb.greenComponent * t,
            blue: ca.blueComponent * (1 - t) + cb.blueComponent * t,
            alpha: 1.0
        )
    }
    
    
    private static func relativeLuminance(_ c: NSColor) -> CGFloat {
        let srgb = c.usingColorSpace(.sRGB) ?? c
        return 0.2126 * srgb.redComponent + 0.7152 * srgb.greenComponent + 0.0722 * srgb.blueComponent
    }
    
    
    private static func saturation(of c: NSColor) -> CGFloat {
        let srgb = c.usingColorSpace(.sRGB) ?? c
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return s
    }
    
    
    private static func ensureDarkModeVisibility(_ c: NSColor) -> NSColor {
        let hsb = c.usingColorSpace(.sRGB) ?? c
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        hsb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let targetB = max(b, 0.74)
        let targetS = min(s, 0.72)
        return NSColor(hue: h, saturation: targetS, brightness: targetB, alpha: 1.0)
    }
    
    
    private static func ensureLightModeTextContrast(_ c: NSColor, against bg: NSColor) -> NSColor {
        let cLum = self.relativeLuminance(c)
        let bgLum = self.relativeLuminance(bg)
        guard abs(bgLum - cLum) < 0.36 else { return c }
        let hsb = c.usingColorSpace(.sRGB) ?? c
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        hsb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(0.92, s * 1.12), brightness: min(b, 0.44), alpha: 1.0)
    }
}
