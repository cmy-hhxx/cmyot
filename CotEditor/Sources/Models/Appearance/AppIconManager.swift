//
//  AppIconManager.swift
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

/// Built-in and user-uploaded artwork sources for the custom App Icon studio.
nonisolated enum AppIconSource: String, CaseIterable, Identifiable, Codable, Sendable {
    
    case preset537
    case presetBaimantou
    case presetXiaoba
    case customImage
    
    var id: String { self.rawValue }
    
    
    var assetName: String? {
        switch self {
            case .preset537: "ChiikawaIcon537"
            case .presetBaimantou: "ChiikawaIconBaimantou"
            case .presetXiaoba: "ChiikawaIconXiaoba"
            case .customImage: nil
        }
    }
    
    
    var displayName: String {
        switch self {
            case .preset537: AppLanguage.text("乌萨奇", en: "Usagi")
            case .presetBaimantou: AppLanguage.text("吉伊卡哇", en: "Chiikawa")
            case .presetXiaoba: AppLanguage.text("小八猫", en: "Hachiware")
            case .customImage: AppLanguage.text("自定义图片", en: "Custom")
        }
    }
    
    
    var tagline: String {
        switch self {
            case .preset537: AppLanguage.text("狂飙码字", en: "Turbo Typing")
            case .presetBaimantou: AppLanguage.text("认真敲键", en: "Focused")
            case .presetXiaoba: AppLanguage.text("灵感在线", en: "Inspired")
            case .customImage: AppLanguage.text("自选原画", en: "Uploaded")
        }
    }
}


/// Curated frame & rim finishes for the App Icon.
nonisolated enum AppIconBorderStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    
    case goldInlay
    case clean
    case platinumSilver
    case obsidianGold
    case ultraViolet
    case signalCrimson
    case matchaGold
    case customColor
    
    var id: String { self.rawValue }
    
    
    var displayName: String {
        switch self {
            case .goldInlay: AppLanguage.text("流光镶金边", en: "Champagne Gold")
            case .clean: AppLanguage.text("纯净超椭圆", en: "Clean Squircle")
            case .platinumSilver: AppLanguage.text("拉丝铂银边", en: "Brushed Platinum")
            case .obsidianGold: AppLanguage.text("黑曜石双金边", en: "Obsidian Gold")
            case .ultraViolet: AppLanguage.text("电光紫罗兰边", en: "Ultra Violet")
            case .signalCrimson: AppLanguage.text("信号绯红漆边", en: "Signal Crimson")
            case .matchaGold: AppLanguage.text("抹茶描金釉", en: "Matcha Glaze")
            case .customColor: AppLanguage.text("自定义色边", en: "Custom Rim")
        }
    }
    
    
    var previewColors: [Color] {
        switch self {
            case .goldInlay:
                [Color(red: 1.0, green: 0.94, blue: 0.68), Color(red: 0.83, green: 0.67, blue: 0.22), Color(red: 0.64, green: 0.45, blue: 0.10)]
            case .clean:
                [Color.white.opacity(0.9), Color.gray.opacity(0.35)]
            case .platinumSilver:
                [Color.white, Color(red: 0.72, green: 0.77, blue: 0.82), Color(red: 0.42, green: 0.46, blue: 0.52)]
            case .obsidianGold:
                [Color(red: 0.06, green: 0.06, blue: 0.09), Color(red: 0.86, green: 0.70, blue: 0.24)]
            case .ultraViolet:
                [Color(red: 0.70, green: 0.62, blue: 0.95), Color(red: 0.44, green: 0.36, blue: 0.70)]
            case .signalCrimson:
                [Color(red: 1.0, green: 0.52, blue: 0.55), Color(red: 0.84, green: 0.22, blue: 0.25)]
            case .matchaGold:
                [Color(red: 0.85, green: 0.98, blue: 0.62), Color(red: 0.64, green: 0.81, blue: 0.27)]
            case .customColor:
                [Color.accentColor, Color.accentColor.opacity(0.65)]
        }
    }
}


/// Optional delicate corner emblem overlaid on the customized App Icon.
nonisolated enum AppIconBadge: String, CaseIterable, Identifiable, Codable, Sendable {
    
    case none
    case goldStar
    case crown
    case sparkle
    case lightning
    
    var id: String { self.rawValue }
    
    
    var displayName: String {
        switch self {
            case .none: AppLanguage.text("无角标", en: "None")
            case .goldStar: AppLanguage.text("星徽", en: "Star")
            case .crown: AppLanguage.text("皇冠", en: "Crown")
            case .sparkle: AppLanguage.text("星芒", en: "Sparkle")
            case .lightning: AppLanguage.text("闪电", en: "Bolt")
        }
    }
    
    
    var symbolName: String? {
        switch self {
            case .none: nil
            case .goldStar: "star.fill"
            case .crown: "crown.fill"
            case .sparkle: "sparkles"
            case .lightning: "bolt.fill"
        }
    }
}


/// Complete user-customizable specification for the dynamic macOS App Icon.
nonisolated struct AppIconSpec: Codable, Equatable, Sendable {
    
    var source: AppIconSource = .preset537
    var borderStyle: AppIconBorderStyle = .goldInlay
    var borderWidth: Double = 4.6       // 0...10
    var imageZoom: Double = 1.0         // 0.80...1.35
    var imageOffsetX: Double = 0.0      // -0.25...0.25
    var imageOffsetY: Double = 0.0      // -0.25...0.25
    var cornerRoundness: Double = 0.225 // 0.16...0.50
    var glossIntensity: Double = 0.35   // 0.0...1.0
    var backgroundMatHex: String = "#161822"
    var customBorderHex: String = "#D4AF37"
    var cornerBadge: AppIconBadge = .none
    
    static let `default` = AppIconSpec()
    
    
    func clamped() -> AppIconSpec {
        var copy = self
        copy.borderWidth = max(0.0, min(10.0, self.borderWidth))
        copy.imageZoom = max(0.80, min(1.35, self.imageZoom))
        copy.imageOffsetX = max(-0.25, min(0.25, self.imageOffsetX))
        copy.imageOffsetY = max(-0.25, min(0.25, self.imageOffsetY))
        copy.cornerRoundness = max(0.16, min(0.50, self.cornerRoundness))
        copy.glossIntensity = max(0.0, min(1.0, self.glossIntensity))
        return copy
    }
}


/// Renders, persists, and live-applies the user's bespoke macOS App Icon across Dock and Finder.
@MainActor @Observable
final class AppIconManager {
    
    static let shared = AppIconManager()
    
    var spec: AppIconSpec {
        didSet {
            guard self.spec != oldValue else { return }
            if self.isReloadingFromDatabase {
                self.refreshPreview()
                return
            }
            if self.database === CotLocalDatabase.shared,
               !Self.isRunningUnitTests,
               self.spec.source == oldValue.source
            {
                self.scheduleDebouncedPersistSpec()
            } else {
                self.persistDebounceTask?.cancel()
                self.persistDebounceTask = nil
                self.persistSpecImmediately()
            }
            self.refreshPreview()
        }
    }
    
    private(set) var customImageVersion: Int = 0
    private(set) var previewRevision: Int = 0
    private(set) var previewImage: NSImage = NSImage()
    
    private let database: CotLocalDatabase
    private let storageDirectory: URL
    private var applyTask: Task<Void, Never>?
    private var dockApplyTask: Task<Void, Never>?
    @ObservationIgnored private var persistDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var cachedCustomImage: NSImage?
    @ObservationIgnored private var isReloadingFromDatabase = false
    
    
    isolated deinit {
        self.persistDebounceTask?.cancel()
        self.applyTask?.cancel()
        self.dockApplyTask?.cancel()
    }
    
    
    init(
        database: CotLocalDatabase = .shared,
        storageDirectory: URL? = nil
    ) {
        self.database = database
        if let storageDirectory {
            self.storageDirectory = storageDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.storageDirectory = appSupport.appending(path: "Cot/CustomAppIcon", directoryHint: .isDirectory)
        }
        
        let rawJSON = database.string(forKey: CotLocalDatabase.ConfigKey.appIconSpecJSON)
        if !rawJSON.isEmpty,
           let data = rawJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(AppIconSpec.self, from: data)
        {
            self.spec = decoded
        } else {
            self.spec = .default
        }
        
        _ = database.restoreMediaBlobsToDisk(
            namespace: .appIcon,
            rootDirectory: self.storageDirectory,
            allowedRelativePaths: ["user-icon.png"],
            overwriteMismatched: false
        )
        
        self.refreshPreview()
    }
    
    
    /// Reloads App Icon spec and custom icon image from the backing database (e.g. after DB import).
    func reloadFromDatabase(overwriteMismatchedBlobs: Bool = false) {
        self.persistDebounceTask?.cancel()
        self.persistDebounceTask = nil
        
        _ = self.database.restoreMediaBlobsToDisk(
            namespace: .appIcon,
            rootDirectory: self.storageDirectory,
            allowedRelativePaths: ["user-icon.png"],
            overwriteMismatched: overwriteMismatchedBlobs
        )
        self.cachedCustomImage = nil
        self.customImageVersion &+= 1
        
        self.isReloadingFromDatabase = true
        let rawJSON = self.database.string(forKey: CotLocalDatabase.ConfigKey.appIconSpecJSON)
        if !rawJSON.isEmpty,
           let data = rawJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(AppIconSpec.self, from: data)
        {
            self.spec = decoded
        } else {
            self.spec = .default
        }
        self.isReloadingFromDatabase = false
        
        self.refreshPreview()
        if !Self.isRunningUnitTests {
            self.applyIconToSystemAndDock()
        }
    }
    
    
    /// Flushes pending spec edits and backfills the custom app icon image into SQLite `media_blobs`.
    func syncBlobsToDatabase() {
        self.persistDebounceTask?.cancel()
        self.persistDebounceTask = nil
        self.persistSpecImmediately()
        if FileManager.default.fileExists(atPath: self.customImageURL.path) {
            self.database.syncDiskFilesToMediaBlobs(
                namespace: .appIcon,
                rootDirectory: self.storageDirectory,
                expectedRelativePaths: ["user-icon.png"],
                pruneUnreferenced: true
            )
        } else {
            self.database.pruneMediaBlobs(in: .appIcon, keepingRelativePaths: [])
        }
    }
    
    
    private var customImageURL: URL {
        self.storageDirectory.appending(path: "user-icon.png")
    }
    
    
    var hasCustomImage: Bool {
        FileManager.default.fileExists(atPath: self.customImageURL.path)
    }
    
    
    func sourceImage(for source: AppIconSource) -> NSImage? {
        switch source {
            case .preset537, .presetBaimantou, .presetXiaoba:
                if let assetName = source.assetName {
                    if let image = NSImage(named: assetName) {
                        return image
                    }
                    // Fallback when unit tests run without full asset catalog lookup
                    if let fallbackPath = Self.fallbackDownloadPath(for: source),
                       let diskImg = NSImage(contentsOfFile: fallbackPath)
                    {
                        return diskImg
                    }
                }
                return nil
                
            case .customImage:
                if let cached = self.cachedCustomImage {
                    return cached
                }
                if !FileManager.default.fileExists(atPath: self.customImageURL.path) {
                    _ = self.database.ensureDiskFileFromMediaBlob(
                        namespace: .appIcon,
                        relativePath: "user-icon.png",
                        rootDirectory: self.storageDirectory
                    )
                }
                if let loaded = NSImage(contentsOf: self.customImageURL) {
                    self.cachedCustomImage = loaded
                    return loaded
                }
                return self.sourceImage(for: .preset537)
        }
    }
    
    
    /// Stores a user-picked image (downsampled cleanly to <= 1280px PNG) and switches `spec.source` to `.customImage`.
    @discardableResult
    func saveCustomImage(_ image: NSImage) -> Bool {
        guard let cg = Self.normalizedCGImage(from: image, maxSide: 1280) else { return false }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        
        do {
            try FileManager.default.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
            try png.write(to: self.customImageURL, options: .atomic)
            self.database.upsertMediaBlob(namespace: .appIcon, relativePath: "user-icon.png", data: png)
            self.cachedCustomImage = NSImage(data: png)
            self.customImageVersion &+= 1
            self.spec.source = .customImage
            self.applyIconToSystemAndDock()
            return true
        } catch {
            return false
        }
    }
    
    
    func resetToDefault() {
        self.spec = .default
        self.applyIconToSystemAndDock()
    }
    
    
    /// Updates icon customization immediately at 120fps in the live preview and debounces heavy 1024px Dock/Finder icon application.
    func updateSpecLive(_ mutate: (inout AppIconSpec) -> Void) {
        var next = self.spec
        mutate(&next)
        let clamped = next.clamped()
        if clamped != self.spec {
            self.spec = clamped
        } else {
            self.refreshPreview()
        }
        self.scheduleDebouncedDockApply()
    }
    
    
    /// Applies the user's saved icon customization on app launch without rewriting default disk icon unnecessarily.
    func applySavedAppIconOnLaunch() {
        let image = self.cachedLaunchRenderedIcon() ?? {
            let rendered = self.renderIcon(size: 1024)
            self.saveLaunchRenderedIconCache(rendered)
            return rendered
        }()
        NSApp.applicationIconImage = image
        guard !Self.isRunningUnitTests else { return }
        if self.spec != .default {
            self.scheduleBundleIconSync(image: image)
        }
    }
    
    
    /// Applies the current spec immediately to the macOS Dock tile and updates the `.app` Finder icon asynchronously.
    func applyIconToSystemAndDock() {
        self.dockApplyTask?.cancel()
        self.refreshPreview()
        let fullIcon = self.renderIcon(size: 1024)
        self.saveLaunchRenderedIconCache(fullIcon)
        NSApp.applicationIconImage = fullIcon
        guard !Self.isRunningUnitTests else { return }
        self.scheduleBundleIconSync(image: fullIcon)
    }
    
    
    /// Renders an authentic macOS squircle App Icon `NSImage` for the given `spec` at pixel dimension `size`.
    func renderIcon(spec customSpec: AppIconSpec? = nil, size: Int = 512) -> NSImage {
        let activeSpec = customSpec ?? self.spec
        let artwork = self.sourceImage(for: activeSpec.source) ?? NSImage(size: NSSize(width: 256, height: 256))
        
        let s = CGFloat(max(32, size))
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(s),
            pixelsHigh: Int(s),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return artwork }
        rep.size = NSSize(width: s, height: s)
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.shouldAntialias = true
        
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: s, height: s).fill()
        
        let bodyRatio: CGFloat = 824.0 / 1024.0
        let bodySide = s * bodyRatio
        let origin = (s - bodySide) * 0.5
        let bodyRect = NSRect(x: origin, y: origin, width: bodySide, height: bodySide)
        let cornerRatio = max(0.14, min(0.50, CGFloat(activeSpec.cornerRoundness)))
        let cornerRadius = bodySide * cornerRatio
        
        // Ambient macOS Dock elevation shadow
        if size >= 64 {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowBlurRadius = max(2, s * 0.030)
            shadow.shadowOffset = NSSize(width: 0, height: -max(1, s * 0.012))
            shadow.set()
            NSColor.black.setFill()
            Self.continuousPath(rect: bodyRect, cornerRadius: cornerRadius).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        
        let outerPath = Self.continuousPath(rect: bodyRect, cornerRadius: cornerRadius)
        
        NSGraphicsContext.saveGraphicsState()
        outerPath.addClip()
        
        // Background mat (visible if user zooms out below 1.0)
        StudioPaletteManager.nsColor(hex: activeSpec.backgroundMatHex).setFill()
        bodyRect.fill()
        
        // Artwork scaled, zoomed, and offset inside the squircle
        let imgSize = artwork.size.width > 0 && artwork.size.height > 0 ? artwork.size : NSSize(width: bodySide, height: bodySide)
        let coverScale = max(bodyRect.width / imgSize.width, bodyRect.height / imgSize.height) * CGFloat(activeSpec.imageZoom)
        let drawW = imgSize.width * coverScale
        let drawH = imgSize.height * coverScale
        let offsetX = CGFloat(activeSpec.imageOffsetX) * bodyRect.width
        let offsetY = CGFloat(activeSpec.imageOffsetY) * bodyRect.height
        let drawRect = NSRect(
            x: bodyRect.midX - drawW * 0.5 + offsetX,
            y: bodyRect.midY - drawH * 0.5 + offsetY,
            width: drawW,
            height: drawH
        )
        artwork.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: false, hints: nil)
        
        // Optional subtle studio diagonal crystal gloss
        if activeSpec.glossIntensity > 0.01 {
            let alpha = min(0.32, CGFloat(activeSpec.glossIntensity) * 0.28)
            if let gloss = NSGradient(colors: [
                NSColor.white.withAlphaComponent(alpha),
                NSColor.white.withAlphaComponent(alpha * 0.16),
                NSColor.clear,
            ]) {
                gloss.draw(in: bodyRect, angle: -72)
            }
        }
        
        NSGraphicsContext.restoreGraphicsState()
        
        // Ornamental frame / gold inlay trim
        Self.drawBorder(for: activeSpec, bodyRect: bodyRect, cornerRadius: cornerRadius, canvasSide: s)
        
        NSGraphicsContext.restoreGraphicsState()
        
        let out = NSImage(size: NSSize(width: s, height: s))
        out.addRepresentation(rep)
        return out
    }
    
    
    // MARK: Private Rendering Helpers
    
    private static func drawBorder(
        for spec: AppIconSpec,
        bodyRect: NSRect,
        cornerRadius: CGFloat,
        canvasSide: CGFloat
    ) {
        let style = spec.borderStyle
        let widthPts = CGFloat(max(0, min(10, spec.borderWidth)))
        
        if style == .clean || widthPts <= 0.1 {
            // Subtle Apple crystal inner top-edge rim even when "Clean"
            let rim = Self.continuousPath(rect: bodyRect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: max(1, cornerRadius - 0.75))
            rim.lineWidth = max(1, canvasSide * 0.0025)
            NSColor.white.withAlphaComponent(0.28).setStroke()
            rim.stroke()
            return
        }
        
        let borderThickness = max(1.2, canvasSide * (widthPts / 100.0) * 0.56)
        let ringRect = bodyRect.insetBy(dx: borderThickness * 0.5, dy: borderThickness * 0.5)
        let ringRadius = max(2, cornerRadius - borderThickness * 0.5)
        
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        
        if style == .obsidianGold {
            // Two-tier obsidian gallery bezel + fine champagne gold inner fillet
            let safeObsidianRadius = min(ringRect.width * 0.5, ringRadius)
            let obsidianCG = CGPath(roundedRect: ringRect, cornerWidth: safeObsidianRadius, cornerHeight: safeObsidianRadius, transform: nil)
            cg.addPath(obsidianCG)
            cg.setLineWidth(borderThickness * 1.15)
            cg.setStrokeColor(NSColor(srgbRed: 0.06, green: 0.06, blue: 0.09, alpha: 1.0).cgColor)
            cg.strokePath()
            
            let goldInset = ringRect.insetBy(dx: borderThickness * 0.65, dy: borderThickness * 0.65)
            let goldRadius = min(goldInset.width * 0.5, max(2, ringRadius - borderThickness * 0.65))
            let goldThickness = max(1.0, borderThickness * 0.36)
            Self.strokeGradientRing(
                in: cg,
                rect: goldInset,
                radius: goldRadius,
                lineWidth: goldThickness,
                gradient: Self.gradient(for: .goldInlay, customHex: spec.customBorderHex)
            )
            cg.restoreGState()
            return
        }
        
        Self.strokeGradientRing(
            in: cg,
            rect: ringRect,
            radius: min(ringRect.width * 0.5, ringRadius),
            lineWidth: borderThickness,
            gradient: Self.gradient(for: style, customHex: spec.customBorderHex)
        )
        
        // Crisp dark inner micro-fillet separating metallic bezel from Chiikawa artwork
        let filletRect = bodyRect.insetBy(dx: borderThickness + 0.5, dy: borderThickness + 0.5)
        let filletPath = Self.continuousPath(rect: filletRect, cornerRadius: max(1, cornerRadius - borderThickness))
        filletPath.lineWidth = max(0.75, canvasSide * 0.0022)
        NSColor.black.withAlphaComponent(0.18).setStroke()
        filletPath.stroke()
        
        cg.restoreGState()
    }
    
    
    private static func strokeGradientRing(
        in cg: CGContext,
        rect: NSRect,
        radius: CGFloat,
        lineWidth: CGFloat,
        gradient: NSGradient
    ) {
        cg.saveGState()
        let safeRadius = min(min(rect.width, rect.height) * 0.5, max(0, radius))
        let path = CGPath(roundedRect: rect, cornerWidth: safeRadius, cornerHeight: safeRadius, transform: nil)
        cg.addPath(path)
        cg.setLineWidth(lineWidth)
        cg.replacePathWithStrokedPath()
        cg.clip()
        gradient.draw(in: rect.insetBy(dx: -lineWidth, dy: -lineWidth), angle: -42)
        cg.restoreGState()
    }
    
    
    private static func gradient(for style: AppIconBorderStyle, customHex: String) -> NSGradient {
        switch style {
            case .goldInlay, .obsidianGold:
                return NSGradient(colorsAndLocations:
                    (NSColor(srgbRed: 1.00, green: 0.94, blue: 0.68, alpha: 1.0), 0.0),
                    (NSColor(srgbRed: 0.83, green: 0.68, blue: 0.22, alpha: 1.0), 0.34),
                    (NSColor(srgbRed: 0.99, green: 0.96, blue: 0.82, alpha: 1.0), 0.62),
                    (NSColor(srgbRed: 0.64, green: 0.45, blue: 0.10, alpha: 1.0), 1.0)
                )!
            case .platinumSilver:
                return NSGradient(colorsAndLocations:
                    (NSColor(srgbRed: 0.99, green: 0.99, blue: 1.00, alpha: 1.0), 0.0),
                    (NSColor(srgbRed: 0.71, green: 0.76, blue: 0.82, alpha: 1.0), 0.40),
                    (NSColor(srgbRed: 0.96, green: 0.98, blue: 1.00, alpha: 1.0), 0.68),
                    (NSColor(srgbRed: 0.44, green: 0.49, blue: 0.56, alpha: 1.0), 1.0)
                )!
            case .ultraViolet:
                return NSGradient(colors: [
                    StudioPaletteManager.nsColor(hex: "#B5A3F2"),
                    StudioPaletteManager.nsColor(hex: "#715CB2"),
                    StudioPaletteManager.nsColor(hex: "#3F2D76"),
                ])!
            case .signalCrimson:
                return NSGradient(colors: [
                    StudioPaletteManager.nsColor(hex: "#FF8B90"),
                    StudioPaletteManager.nsColor(hex: "#D53740"),
                    StudioPaletteManager.nsColor(hex: "#7D161D"),
                ])!
            case .matchaGold:
                return NSGradient(colorsAndLocations:
                    (StudioPaletteManager.nsColor(hex: "#DCF996"), 0.0),
                    (StudioPaletteManager.nsColor(hex: "#A4CE46"), 0.50),
                    (StudioPaletteManager.nsColor(hex: "#D4AF37"), 0.80),
                    (StudioPaletteManager.nsColor(hex: "#587C18"), 1.0)
                )!
            case .customColor:
                let base = StudioPaletteManager.nsColor(hex: customHex)
                let hi = base.blended(withFraction: 0.42, of: .white) ?? base
                let lo = base.blended(withFraction: 0.34, of: .black) ?? base
                return NSGradient(colors: [hi, base, hi, lo])!
            case .clean:
                return NSGradient(colors: [.white, .lightGray])!
        }
    }
    
    
    private static func continuousPath(rect: NSRect, cornerRadius: CGFloat) -> NSBezierPath {
        let clampedRadius = min(min(rect.width, rect.height) * 0.5, max(0, cornerRadius))
        return NSBezierPath(roundedRect: rect, xRadius: clampedRadius, yRadius: clampedRadius)
    }
    
    
    private var launchCacheImageURL: URL {
        self.storageDirectory.appending(path: "launch-icon-1024.png")
    }
    
    
    private var launchCacheMetaURL: URL {
        self.storageDirectory.appending(path: "launch-icon-meta.json")
    }
    
    
    private func launchCacheFingerprint() -> String? {
        guard let specData = try? JSONEncoder().encode(self.spec),
              let specJSON = String(data: specData, encoding: .utf8)
        else { return nil }
        var customMod: TimeInterval = 0
        if self.spec.source == .customImage,
           let attrs = try? FileManager.default.attributesOfItem(atPath: self.customImageURL.path),
           let modDate = attrs[.modificationDate] as? Date
        {
            customMod = modDate.timeIntervalSince1970
        }
        return "\(specJSON)|\(customMod)"
    }
    
    
    private func cachedLaunchRenderedIcon() -> NSImage? {
        guard let expected = self.launchCacheFingerprint(),
              let metaData = try? Data(contentsOf: self.launchCacheMetaURL),
              let saved = String(data: metaData, encoding: .utf8),
              saved == expected,
              let img = NSImage(contentsOf: self.launchCacheImageURL)
        else { return nil }
        return img
    }
    
    
    private func saveLaunchRenderedIconCache(_ image: NSImage) {
        guard let fingerprint = self.launchCacheFingerprint(),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return }
        try? FileManager.default.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
        try? png.write(to: self.launchCacheImageURL, options: .atomic)
        try? Data(fingerprint.utf8).write(to: self.launchCacheMetaURL, options: .atomic)
    }
    
    
    private func scheduleDebouncedPersistSpec() {
        self.persistDebounceTask?.cancel()
        self.persistDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.persistSpecImmediately()
        }
    }
    
    
    private func persistSpecImmediately() {
        if let data = try? JSONEncoder().encode(self.spec),
           let json = String(data: data, encoding: .utf8)
        {
            self.database.set(json, forKey: CotLocalDatabase.ConfigKey.appIconSpecJSON)
        }
    }
    
    
    private func refreshPreview() {
        self.previewImage = self.renderIcon(size: 256)
        self.previewRevision &+= 1
    }
    
    
    private func scheduleDebouncedDockApply() {
        self.dockApplyTask?.cancel()
        self.dockApplyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled, let self else { return }
            let fullIcon = self.renderIcon(size: 1024)
            self.saveLaunchRenderedIconCache(fullIcon)
            NSApp.applicationIconImage = fullIcon
            guard !Self.isRunningUnitTests else { return }
            self.scheduleBundleIconSync(image: fullIcon)
        }
    }
    
    
    private func scheduleBundleIconSync(image: NSImage) {
        let bundlePath = Bundle.main.bundleURL.path
        guard bundlePath.hasSuffix(".app") else { return }
        self.applyTask?.cancel()
        self.applyTask = Task {
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            NSWorkspace.shared.setIcon(image, forFile: bundlePath, options: [])
        }
    }
    
    
    private static func fallbackDownloadPath(for source: AppIconSource) -> String? {
        switch source {
            case .preset537: "/Users/cmy/Downloads/CoTEditor_icons/icon_537.jpg"
            case .presetBaimantou: "/Users/cmy/Downloads/CoTEditor_icons/icon_baimantou.jpg"
            case .presetXiaoba: "/Users/cmy/Downloads/CoTEditor_icons/icon_xiaoba.jpg"
            case .customImage: nil
        }
    }
    
    
    private static func normalizedCGImage(from image: NSImage, maxSide: CGFloat) -> CGImage? {
        let rawSize = image.size
        guard rawSize.width > 0, rawSize.height > 0 else { return nil }
        let ratio = min(1.0, maxSide / max(rawSize.width, rawSize.height))
        let w = max(1, Int((rawSize.width * ratio).rounded()))
        let h = max(1, Int((rawSize.height * ratio).rounded()))
        guard let rep = NSBitmapImageRep(
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
        ) else { return nil }
        rep.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
    
    
    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }
}
