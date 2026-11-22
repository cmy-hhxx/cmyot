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

/// Global high-fashion editorial palette presets inspired by curated 3-color design triads.
nonisolated enum StudioPaletteID: String, CaseIterable, Identifiable, Codable, Sendable {
    
    case ultraViolet
    case signalCrimson
    case matchaParchment
    case pineCeladon
    case custom
    
    var id: String { self.rawValue }
    
    
    var displayName: String {
        switch self {
            case .ultraViolet: AppLanguage.text("电光紫罗兰", en: "Ultra Violet")
            case .signalCrimson: AppLanguage.text("信号绯红", en: "Signal Crimson")
            case .matchaParchment: AppLanguage.text("抹茶荧光绿", en: "Matcha Marker")
            case .pineCeladon: AppLanguage.text("松烟青玉", en: "Pine Celadon")
            case .custom: AppLanguage.text("自定义三色", en: "Custom Triad")
        }
    }
    
    
    var subtitle: String {
        switch self {
            case .ultraViolet: "MIDNIGHT · SILVER · ULTRA VIOLET"
            case .signalCrimson: "CLOUD · CARBON · CRIMSON"
            case .matchaParchment: "PARCHMENT · INK · MATCHA"
            case .pineCeladon: "XUAN · PINE INK · CELADON"
            case .custom: "CUSTOM DESIGNER TRIAD"
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
    
    var customLightHex: String {
        didSet {
            self.database.set(self.customLightHex, forKey: CotLocalDatabase.ConfigKey.studioCustomLightHex)
            if self.selectedID == .custom {
                self.postPaletteChange()
            }
        }
    }
    
    var customDarkHex: String {
        didSet {
            self.database.set(self.customDarkHex, forKey: CotLocalDatabase.ConfigKey.studioCustomDarkHex)
            if self.selectedID == .custom {
                self.postPaletteChange()
            }
        }
    }
    
    var customAccentHex: String {
        didSet {
            self.database.set(self.customAccentHex, forKey: CotLocalDatabase.ConfigKey.studioCustomAccentHex)
            if self.selectedID == .custom {
                self.postPaletteChange()
            }
        }
    }
    
    /// Incremented monotonically whenever active tokens change, making SwiftUI observation explicit.
    private(set) var revision: Int = 0
    
    private let database: CotLocalDatabase
    
    
    init(database: CotLocalDatabase = .shared) {
        self.database = database
        let rawID = database.string(
            forKey: CotLocalDatabase.ConfigKey.studioPaletteID,
            default: StudioPaletteID.ultraViolet.rawValue
        )
        self.selectedID = StudioPaletteID(rawValue: rawID) ?? .ultraViolet
        self.customLightHex = database.string(forKey: CotLocalDatabase.ConfigKey.studioCustomLightHex, default: "#EDEBE6")
        self.customDarkHex = database.string(forKey: CotLocalDatabase.ConfigKey.studioCustomDarkHex, default: "#121318")
        self.customAccentHex = database.string(forKey: CotLocalDatabase.ConfigKey.studioCustomAccentHex, default: "#715CB2")
    }
    
    
    /// Reloads palette selection & custom triad hexes from the backing database (e.g. after DB import or profile switch).
    func reloadFromDatabase() {
        let rawID = self.database.string(
            forKey: CotLocalDatabase.ConfigKey.studioPaletteID,
            default: StudioPaletteID.ultraViolet.rawValue
        )
        self.selectedID = StudioPaletteID(rawValue: rawID) ?? .ultraViolet
        self.customLightHex = self.database.string(forKey: CotLocalDatabase.ConfigKey.studioCustomLightHex, default: "#EDEBE6")
        self.customDarkHex = self.database.string(forKey: CotLocalDatabase.ConfigKey.studioCustomDarkHex, default: "#121318")
        self.customAccentHex = self.database.string(forKey: CotLocalDatabase.ConfigKey.studioCustomAccentHex, default: "#715CB2")
        self.postPaletteChange()
    }
    
    
    private func postPaletteChange() {
        self.revision &+= 1
        NotificationCenter.default.post(name: Self.paletteDidChangeNotification, object: self)
    }
    
    
    func selectPalette(_ id: StudioPaletteID) {
        self.selectedID = id
    }
    
    
    func triad(for id: StudioPaletteID? = nil) -> StudioPaletteTriad {
        let resolvedID = id ?? self.selectedID
        switch resolvedID {
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
            case .pineCeladon:
                return StudioPaletteTriad(
                    lightPaperHex: "#F2F3EF",
                    lightPaperName: AppLanguage.text("宣纸素白", en: "Xuan Paper"),
                    darkInkHex: "#111413",
                    darkInkName: AppLanguage.text("松烟墨黑", en: "Pine Ink"),
                    accentHex: "#2E8B67",
                    accentName: AppLanguage.text("青玉松翠", en: "Celadon Pine")
                )
            case .custom:
                return StudioPaletteTriad(
                    lightPaperHex: self.customLightHex,
                    lightPaperName: AppLanguage.text("浅底纸色", en: "Light Surface"),
                    darkInkHex: self.customDarkHex,
                    darkInkName: AppLanguage.text("深底墨色", en: "Dark Ink"),
                    accentHex: self.customAccentHex,
                    accentName: AppLanguage.text("点睛主色", en: "Signature Accent")
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
        let _ = self.revision
        let resolvedID = id ?? self.selectedID
        let triad = self.triad(for: resolvedID)
        
        let lightPaperNS = Self.nsColor(hex: triad.lightPaperHex)
        let darkInkNS = Self.nsColor(hex: triad.darkInkHex)
        let accentNS = Self.nsColor(hex: triad.accentHex)
        
        if isDark {
            let canvasTopNS = darkInkNS
            let canvasBottomNS = Self.blend(darkInkNS, with: .white, ratio: 0.03)
            let cardNS = Self.blend(darkInkNS, with: .white, ratio: 0.06)
            let insetNS = Self.blend(darkInkNS, with: .white, ratio: 0.11)
            let insetHoverNS = Self.blend(darkInkNS, with: .white, ratio: 0.16)
            let emptyDotNS = Self.blend(darkInkNS, with: .white, ratio: 0.12)
            let primaryInkNS = lightPaperNS
            let liftedAccentNS = Self.ensureDarkModeVisibility(accentNS)
            let secondaryAccentNS = Self.blend(liftedAccentNS, with: darkInkNS, ratio: 0.30)
            let paleAccentNS = Self.blend(liftedAccentNS, with: darkInkNS, ratio: 0.65)
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
                hairline: Color.white.opacity(0.09),
                hairlineStrong: Color(nsColor: liftedAccentNS).opacity(0.55),
                topSpecular: Color.white.opacity(0.08),
                architecturalDot: Color.white.opacity(0.045),
                primaryInk: Color(nsColor: primaryInkNS),
                accent: Color(nsColor: accentNS),
                accentText: Color(nsColor: liftedAccentNS),
                onAccentInk: Color(nsColor: onAccentInkNS),
                secondaryAccent: Color(nsColor: secondaryAccentNS),
                paleAccent: Color(nsColor: paleAccentNS),
                emptyDot: Color(nsColor: emptyDotNS),
                positivePillBg: Color(nsColor: accentNS).opacity(0.20),
                neutralPillBg: Color.white.opacity(0.08),
                heat1: Color(nsColor: Self.blend(darkInkNS, with: liftedAccentNS, ratio: 0.24)),
                heat2: Color(nsColor: Self.blend(darkInkNS, with: liftedAccentNS, ratio: 0.45)),
                heat3: Color(nsColor: Self.blend(darkInkNS, with: liftedAccentNS, ratio: 0.72)),
                heat4: Color(nsColor: liftedAccentNS)
            )
        } else {
            let isMatcha = (resolvedID == .matchaParchment)
            let canvasTopNS = isMatcha
                ? Self.blend(lightPaperNS, with: .white, ratio: 0.14)
                : lightPaperNS
            let canvasBottomNS = isMatcha
                ? lightPaperNS
                : Self.blend(lightPaperNS, with: .white, ratio: 0.35)
            let cardNS = isMatcha
                ? Self.blend(lightPaperNS, with: .white, ratio: 0.62)
                : Self.blend(lightPaperNS, with: .white, ratio: 0.82)
            let insetNS = Self.blend(lightPaperNS, with: darkInkNS, ratio: 0.055)
            let insetHoverNS = Self.blend(lightPaperNS, with: darkInkNS, ratio: 0.105)
            let emptyDotNS = Self.blend(lightPaperNS, with: darkInkNS, ratio: 0.10)
            
            // Small text needs sufficient contrast on light paper (especially lime #A4CE46 on cream #E7DBB8).
            let readableAccentTextNS = Self.ensureLightModeTextContrast(accentNS, against: cardNS)
            let secondaryAccentNS = Self.blend(accentNS, with: lightPaperNS, ratio: 0.36)
            let paleAccentNS = Self.blend(accentNS, with: lightPaperNS, ratio: 0.72)
            let onAccentInkNS = Self.relativeLuminance(accentNS) > 0.48
                ? darkInkNS
                : NSColor.white
            
            return StudioColorTokens(
                isDark: false,
                canvasTop: Color(nsColor: canvasTopNS),
                canvasBottom: Color(nsColor: canvasBottomNS),
                mistAccent: Color(nsColor: accentNS).opacity(0.14),
                card: Color(nsColor: cardNS),
                cardShadow: Color(nsColor: darkInkNS).opacity(0.065),
                inset: Color(nsColor: insetNS),
                insetHover: Color(nsColor: insetHoverNS),
                hairline: Color(nsColor: darkInkNS).opacity(0.085),
                hairlineStrong: Color(nsColor: accentNS).opacity(0.45),
                topSpecular: Color.white.opacity(0.75),
                architecturalDot: Color(nsColor: darkInkNS).opacity(0.05),
                primaryInk: Color(nsColor: darkInkNS),
                accent: Color(nsColor: accentNS),
                accentText: Color(nsColor: readableAccentTextNS),
                onAccentInk: Color(nsColor: onAccentInkNS),
                secondaryAccent: Color(nsColor: secondaryAccentNS),
                paleAccent: Color(nsColor: paleAccentNS),
                emptyDot: Color(nsColor: emptyDotNS),
                positivePillBg: Color(nsColor: accentNS).opacity(isMatcha ? 0.28 : 0.14),
                neutralPillBg: Color(nsColor: darkInkNS).opacity(0.055),
                heat1: Color(nsColor: Self.blend(lightPaperNS, with: accentNS, ratio: 0.28)),
                heat2: Color(nsColor: Self.blend(lightPaperNS, with: accentNS, ratio: 0.52)),
                heat3: Color(nsColor: Self.blend(lightPaperNS, with: accentNS, ratio: 0.76)),
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
    
    
    /// Synthesizes any built-in `Studio · ...` editor theme by name (Chinese or English) so migrating
    /// a database to another machine never fails with a missing theme resource error.
    func synthesizedTheme(named name: String) -> Theme? {
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
        
        let matchedID: StudioPaletteID = switch baseTitle {
            case "电光紫罗兰", "Ultra Violet": .ultraViolet
            case "信号绯红", "Signal Crimson": .signalCrimson
            case "抹茶荧光绿", "Matcha Marker": .matchaParchment
            case "松烟青玉", "Pine Celadon": .pineCeladon
            case "自定义三色", "Custom Triad": .custom
            default: self.selectedID
        }
        return self.buildTheme(for: matchedID, preferDark: preferDark)
    }
    
    
    /// Creates or updates a user editor syntax `Theme` matching the active Studio Palette and selects it.
    func applyPaletteToEditorTheme(preferDark: Bool) {
        let themeName = "Studio · \(self.selectedID.displayName) (\(preferDark ? AppLanguage.text("暗色", en: "Dark") : AppLanguage.text("浅色", en: "Light")))"
        let theme = self.buildTheme(for: self.selectedID, preferDark: preferDark)
        
        try? ThemeManager.shared.save(setting: theme, name: themeName)
        UserDefaults.standard[.theme] = themeName
        UserDefaults.standard[.pinsThemeAppearance] = true
        UserDefaults.standard[.documentAppearance] = preferDark ? AppearanceMode.dark : AppearanceMode.light
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
