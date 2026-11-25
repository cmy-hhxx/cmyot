//
//  WallpaperManager.swift
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
import CoreImage
import ImageIO
import Observation
import SwiftUI

nonisolated enum WallpaperDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    
    case fill
    case fit
    case center
    
    var id: String { self.rawValue }
    
    var label: String {
        switch self {
            case .fill: AppLanguage.text("充满", en: "Fill")
            case .fit: AppLanguage.text("适应", en: "Fit")
            case .center: AppLanguage.text("居中", en: "Center")
        }
    }
    
    var minScale: Double {
        switch self {
            case .fill: 1.0
            case .fit, .center: 0.5
        }
    }
    
    static let maxScale: Double = 4.0
}


nonisolated struct WallpaperFraming: Codable, Equatable, Sendable {
    
    var scale: Double = 1.0          // 1.0 ... 4.0 (fill), 0.5 ... 4.0 (fit / center)
    var panX: Double = 0.0           // -1.0 ... 1.0
    var panY: Double = 0.0           // -1.0 ... 1.0
    var displayMode: WallpaperDisplayMode = .fill
    
    enum CodingKeys: String, CodingKey {
        case scale, panX, panY, displayMode
    }
    
    init(
        scale: Double = 1.0,
        panX: Double = 0.0,
        panY: Double = 0.0,
        displayMode: WallpaperDisplayMode = .fill
    ) {
        self.scale = scale
        self.panX = panX
        self.panY = panY
        self.displayMode = displayMode
    }
    
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        self.panX = try c.decodeIfPresent(Double.self, forKey: .panX) ?? 0.0
        self.panY = try c.decodeIfPresent(Double.self, forKey: .panY) ?? 0.0
        self.displayMode = try c.decodeIfPresent(WallpaperDisplayMode.self, forKey: .displayMode) ?? .fill
    }
    
    var isDefault: Bool {
        abs(self.scale - 1.0) < 0.005
            && abs(self.panX) < 0.005
            && abs(self.panY) < 0.005
            && self.displayMode == .fill
    }
    
    func clamped() -> WallpaperFraming {
        WallpaperFraming(
            scale: max(self.displayMode.minScale, min(WallpaperDisplayMode.maxScale, self.scale)),
            panX: max(-1.0, min(1.0, self.panX)),
            panY: max(-1.0, min(1.0, self.panY)),
            displayMode: self.displayMode
        )
    }
}


nonisolated struct WallpaperSpec: Codable, Equatable, Sendable {
    
    var isEnabled: Bool = false
    var selectedID: String = "ink-aurora"
    var opacity: Double = 0.16      // 0.04 ... 0.85
    var blurRadius: Double = 10.0   // 0.0 ... 40.0
    var scale: Double = 1.0         // 0.5 ... 4.0
    var panX: Double = 0.0          // -1.0 ... 1.0
    var panY: Double = 0.0          // -1.0 ... 1.0
    var displayMode: WallpaperDisplayMode = .fill
    var perItemFraming: [String: WallpaperFraming] = [:]
    
    static let `default` = WallpaperSpec()
    
    enum CodingKeys: String, CodingKey {
        case isEnabled, selectedID, opacity, blurRadius, scale, panX, panY, displayMode, perItemFraming
    }
    
    init(
        isEnabled: Bool = false,
        selectedID: String = "ink-aurora",
        opacity: Double = 0.16,
        blurRadius: Double = 10.0,
        scale: Double = 1.0,
        panX: Double = 0.0,
        panY: Double = 0.0,
        displayMode: WallpaperDisplayMode = .fill,
        perItemFraming: [String: WallpaperFraming] = [:]
    ) {
        self.isEnabled = isEnabled
        self.selectedID = selectedID
        self.opacity = opacity
        self.blurRadius = blurRadius
        self.scale = scale
        self.panX = panX
        self.panY = panY
        self.displayMode = displayMode
        self.perItemFraming = perItemFraming
    }
    
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        self.selectedID = try c.decodeIfPresent(String.self, forKey: .selectedID) ?? "ink-aurora"
        self.opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.16
        self.blurRadius = try c.decodeIfPresent(Double.self, forKey: .blurRadius) ?? 10.0
        self.scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        self.panX = try c.decodeIfPresent(Double.self, forKey: .panX) ?? 0.0
        self.panY = try c.decodeIfPresent(Double.self, forKey: .panY) ?? 0.0
        self.displayMode = try c.decodeIfPresent(WallpaperDisplayMode.self, forKey: .displayMode) ?? .fill
        self.perItemFraming = try c.decodeIfPresent([String: WallpaperFraming].self, forKey: .perItemFraming) ?? [:]
    }
    
    var currentFraming: WallpaperFraming {
        WallpaperFraming(scale: self.scale, panX: self.panX, panY: self.panY, displayMode: self.displayMode).clamped()
    }
    
    func clamped() -> WallpaperSpec {
        var copy = self
        copy.opacity = max(0.04, min(0.85, self.opacity))
        copy.blurRadius = max(0.0, min(40.0, self.blurRadius))
        let framing = WallpaperFraming(scale: self.scale, panX: self.panX, panY: self.panY, displayMode: self.displayMode).clamped()
        copy.scale = framing.scale
        copy.panX = framing.panX
        copy.panY = framing.panY
        copy.displayMode = framing.displayMode
        copy.perItemFraming = self.perItemFraming.mapValues { $0.clamped() }
        if copy.selectedID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.selectedID = "ink-aurora"
        }
        return copy
    }
}


nonisolated struct WallpaperCustomRecord: Codable, Equatable, Identifiable, Sendable {
    
    let id: String
    var title: String
    var filename: String
    var createdAt: Date
}


nonisolated struct WallpaperItem: Identifiable, Equatable, Sendable {
    
    let id: String
    let title: String
    let subtitle: String
    let isCustom: Bool
    let accentHex: String
    let paletteHexes: [String]
}


/// Manages curated studio wallpapers and user-uploaded custom images,
/// providing CoreImage pre-blurred backdrop rendering for the editor canvas.
@MainActor @Observable
final class WallpaperManager {
    
    static let shared = WallpaperManager()
    static let didChangeNotification = Notification.Name("CotEditorWallpaperDidChange")
    
    static let builtInItems: [WallpaperItem] = [
        WallpaperItem(id: "ink-aurora", title: "松烟山岚", subtitle: "PINE MIST", isCustom: false, accentHex: "#44C997", paletteHexes: ["#0B1714", "#173A2F", "#44C997"]),
        WallpaperItem(id: "starry-indigo", title: "午夜星云", subtitle: "ULTRA VIOLET", isCustom: false, accentHex: "#8772D6", paletteHexes: ["#0D0D1A", "#251D4A", "#715CB2"]),
        WallpaperItem(id: "crimson-darkroom", title: "绯红暗房", subtitle: "SIGNAL RED", isCustom: false, accentHex: "#E0444D", paletteHexes: ["#120E10", "#3D151B", "#D53740"]),
        WallpaperItem(id: "matcha-washi", title: "抹茶和纸", subtitle: "MATCHA PAPER", isCustom: false, accentHex: "#7FB030", paletteHexes: ["#EFE7CE", "#DDE7BD", "#A4CE46"]),
        WallpaperItem(id: "amber-dawn", title: "琥珀晨雾", subtitle: "AMBER MIST", isCustom: false, accentHex: "#E5A93C", paletteHexes: ["#1C140C", "#422A14", "#E5A93C"]),
        WallpaperItem(id: "whale-abyss", title: "深海鲸歌", subtitle: "ABYSS BLUE", isCustom: false, accentHex: "#3C8CE7", paletteHexes: ["#081628", "#10345C", "#3C8CE7"]),
        WallpaperItem(id: "blossom-silk", title: "樱雾素绢", subtitle: "SAKURA VEIL", isCustom: false, accentHex: "#DE7898", paletteHexes: ["#F6ECEF", "#EAD2DA", "#DE7898"]),
    ]
    
    var spec: WallpaperSpec {
        didSet {
            var normalized = self.spec.clamped()
            let currentFraming = normalized.currentFraming
            if currentFraming.isDefault {
                normalized.perItemFraming.removeValue(forKey: normalized.selectedID)
            } else {
                normalized.perItemFraming[normalized.selectedID] = currentFraming
            }
            if normalized != self.spec {
                self.spec = normalized
                return
            }
            if !self.spec.isEnabled {
                self.clearTransientImageCaches()
            }
            if self.shouldDebouncePersist(from: oldValue, to: self.spec) {
                self.scheduleDebouncedPersistSpec()
            } else {
                self.persistDebounceTask?.cancel()
                self.persistDebounceTask = nil
                self.persistSpecImmediately()
            }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }
    
    private(set) var customRecords: [WallpaperCustomRecord] = []
    private(set) var catalogVersion: Int = 0
    
    private let database: CotLocalDatabase
    private let storageDirectory: URL
    @ObservationIgnored private lazy var ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let rawImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        cache.countLimit = 12
        return cache
    }()
    private let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 16 * 1024 * 1024
        cache.countLimit = 48
        return cache
    }()
    private let blurredImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        cache.countLimit = 16
        return cache
    }()
    @ObservationIgnored private var persistDebounceTask: Task<Void, Never>?
    
    
    isolated deinit {
        self.persistDebounceTask?.cancel()
    }
    
    
    var allItems: [WallpaperItem] {
        let custom = self.customRecords.reversed().map { record in
            WallpaperItem(
                id: record.id,
                title: record.title,
                subtitle: "CUSTOM",
                isCustom: true,
                accentHex: "#715CB2",
                paletteHexes: ["#1D1F28", "#353A4A", "#715CB2"]
            )
        }
        return custom + Self.builtInItems
    }
    
    
    init(database: CotLocalDatabase = .shared, storageDirectory: URL? = nil) {
        self.database = database
        if let storageDirectory {
            self.storageDirectory = storageDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            self.storageDirectory = appSupport
                .appending(path: "CotEditor", directoryHint: .isDirectory)
                .appending(path: "Wallpapers", directoryHint: .isDirectory)
        }
        
        let rawSpec = database.string(forKey: CotLocalDatabase.ConfigKey.editorWallpaperSpecJSON)
        if let data = rawSpec.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(WallpaperSpec.self, from: data)
        {
            self.spec = decoded.clamped()
        } else {
            self.spec = .default
        }
        
        let rawCustom = database.string(forKey: CotLocalDatabase.ConfigKey.editorWallpaperCustomCatalogJSON)
        if let data = rawCustom.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([WallpaperCustomRecord].self, from: data)
        {
            self.customRecords = decoded
        }
    }
    
    
    /// Reloads wallpaper spec and custom catalog from the backing database (e.g. after DB import).
    func reloadFromDatabase() {
        let rawSpec = self.database.string(forKey: CotLocalDatabase.ConfigKey.editorWallpaperSpecJSON)
        if let data = rawSpec.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(WallpaperSpec.self, from: data)
        {
            self.spec = decoded.clamped()
        } else {
            self.spec = .default
        }
        let rawCustom = self.database.string(forKey: CotLocalDatabase.ConfigKey.editorWallpaperCustomCatalogJSON)
        if let data = rawCustom.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([WallpaperCustomRecord].self, from: data)
        {
            self.customRecords = decoded
        } else {
            self.customRecords = []
        }
        self.rawImageCache.removeAllObjects()
        self.thumbnailCache.removeAllObjects()
        self.blurredImageCache.removeAllObjects()
        self.catalogVersion += 1
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
    
    
    /// Selects a wallpaper by ID, saving the previous item's crop framing and restoring the target item's framing.
    func selectWallpaper(id: String, enableIfDisabled: Bool = true) {
        var next = self.spec
        let previousID = next.selectedID
        let previousFraming = next.currentFraming
        if previousFraming.isDefault {
            next.perItemFraming.removeValue(forKey: previousID)
        } else {
            next.perItemFraming[previousID] = previousFraming
        }
        
        let restored = next.perItemFraming[id]?.clamped() ?? WallpaperFraming()
        next.selectedID = id
        next.scale = restored.scale
        next.panX = restored.panX
        next.panY = restored.panY
        next.displayMode = restored.displayMode
        if enableIfDisabled {
            next.isEnabled = true
        }
        self.spec = next
    }
    
    
    /// Updates interactive crop/pan/zoom/mode framing for the active wallpaper.
    func updateFraming(
        scale: Double? = nil,
        panX: Double? = nil,
        panY: Double? = nil,
        displayMode: WallpaperDisplayMode? = nil
    ) {
        var next = self.spec
        if let displayMode { next.displayMode = displayMode }
        if let scale { next.scale = scale }
        if let panX { next.panX = panX }
        if let panY { next.panY = panY }
        self.spec = next
    }
    
    
    /// Resets crop/pan/zoom framing for the active wallpaper back to centered aspect-fill.
    func resetFraming() {
        var next = self.spec
        next.scale = 1.0
        next.panX = 0.0
        next.panY = 0.0
        next.displayMode = .fill
        next.perItemFraming.removeValue(forKey: next.selectedID)
        self.spec = next
    }
    
    
    /// Returns the authentic aspect ratio of the active editor window (or primary Mac display) for faithful preview framing.
    static func referenceWindowAspectRatio() -> CGFloat {
        if let docWindow = NSApp.orderedWindows.first(where: { $0.windowController is DocumentWindowController && $0.isVisible }),
           let contentView = docWindow.contentView,
           contentView.bounds.height > 120
        {
            let ratio = contentView.bounds.width / contentView.bounds.height
            return max(1.15, min(2.25, ratio))
        }
        if let screen = NSScreen.main ?? NSScreen.screens.first, screen.frame.height > 0 {
            let ratio = screen.frame.width / screen.frame.height
            return max(1.25, min(2.10, ratio))
        }
        return 16.0 / 10.0
    }
    
    
    /// Computes the exact draw rect across Fill, Fit, and Center modes for both flipped SwiftUI previews and unflipped AppKit backdrops.
    nonisolated static func framedDrawRect(
        imageSize: CGSize,
        viewportSize: CGSize,
        scale: Double,
        panX: Double,
        panY: Double,
        isFlippedY: Bool,
        displayMode: WallpaperDisplayMode = .fill
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0
        else { return .zero }
        
        let clamped = WallpaperFraming(scale: scale, panX: panX, panY: panY, displayMode: displayMode).clamped()
        let baseScale: CGFloat = switch displayMode {
            case .fill:
                max(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
            case .fit, .center:
                min(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
        }
        let drawW = imageSize.width * baseScale * CGFloat(clamped.scale)
        let drawH = imageSize.height * baseScale * CGFloat(clamped.scale)
        let ySign: CGFloat = isFlippedY ? -1.0 : 1.0
        
        switch displayMode {
            case .fill:
                let slackX = max(0, (drawW - viewportSize.width) * 0.5)
                let slackY = max(0, (drawH - viewportSize.height) * 0.5)
                let originX = (viewportSize.width - drawW) * 0.5 - CGFloat(clamped.panX) * slackX
                let originY = (viewportSize.height - drawH) * 0.5 + ySign * CGFloat(clamped.panY) * slackY
                return CGRect(x: originX, y: originY, width: drawW, height: drawH)
                
            case .fit:
                let originX: CGFloat = if drawW >= viewportSize.width {
                    (viewportSize.width - drawW) * 0.5 - CGFloat(clamped.panX) * ((drawW - viewportSize.width) * 0.5)
                } else {
                    (viewportSize.width - drawW) * 0.5 + CGFloat(clamped.panX) * ((viewportSize.width - drawW) * 0.5)
                }
                let originY: CGFloat = if drawH >= viewportSize.height {
                    (viewportSize.height - drawH) * 0.5 + ySign * CGFloat(clamped.panY) * ((drawH - viewportSize.height) * 0.5)
                } else {
                    (viewportSize.height - drawH) * 0.5 - ySign * CGFloat(clamped.panY) * ((viewportSize.height - drawH) * 0.5)
                }
                return CGRect(x: originX, y: originY, width: drawW, height: drawH)
                
            case .center:
                let travelX = max(abs(drawW - viewportSize.width) * 0.5, (drawW + viewportSize.width) * 0.32)
                let travelY = max(abs(drawH - viewportSize.height) * 0.5, (drawH + viewportSize.height) * 0.32)
                let originX = (viewportSize.width - drawW) * 0.5 - CGFloat(clamped.panX) * travelX
                let originY = (viewportSize.height - drawH) * 0.5 + ySign * CGFloat(clamped.panY) * travelY
                return CGRect(x: originX, y: originY, width: drawW, height: drawH)
        }
    }
    
    
    /// Computes updated crop/pan framing from a drag translation vector inside a top-left-origin viewport.
    nonisolated static func dragUpdatedFraming(
        start: WallpaperFraming,
        imageSize: CGSize,
        viewportSize: CGSize,
        translation: CGSize
    ) -> WallpaperFraming {
        let clampedStart = start.clamped()
        guard imageSize.width > 0, imageSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0
        else { return clampedStart }
        
        let mode = clampedStart.displayMode
        let baseScale: CGFloat = (mode == .fill)
            ? max(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
            : min(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
        
        switch mode {
            case .fill:
                let baseW = imageSize.width * baseScale * CGFloat(clampedStart.scale)
                let baseH = imageSize.height * baseScale * CGFloat(clampedStart.scale)
                let baseSlackX = max(0, (baseW - viewportSize.width) * 0.5)
                let baseSlackY = max(0, (baseH - viewportSize.height) * 0.5)
                
                // If aspect ratio nearly matches the viewport at 1.0x, smoothly nudge zoom so dragging always frames freely.
                let effectiveScale = (baseSlackX < 3 && baseSlackY < 3) ? max(clampedStart.scale, 1.22) : clampedStart.scale
                let effW = imageSize.width * baseScale * CGFloat(effectiveScale)
                let effH = imageSize.height * baseScale * CGFloat(effectiveScale)
                let slackX = max(0, (effW - viewportSize.width) * 0.5)
                let slackY = max(0, (effH - viewportSize.height) * 0.5)
                
                let nextPanX = slackX > 1 ? clampedStart.panX - Double(translation.width / slackX) : clampedStart.panX
                let nextPanY = slackY > 1 ? clampedStart.panY - Double(translation.height / slackY) : clampedStart.panY
                return WallpaperFraming(scale: effectiveScale, panX: nextPanX, panY: nextPanY, displayMode: .fill).clamped()
                
            case .fit:
                let drawW = imageSize.width * baseScale * CGFloat(clampedStart.scale)
                let drawH = imageSize.height * baseScale * CGFloat(clampedStart.scale)
                let diffX = drawW - viewportSize.width
                let diffY = drawH - viewportSize.height
                let nextPanX: Double = abs(diffX) > 1
                    ? clampedStart.panX + (diffX >= 0 ? -1.0 : 1.0) * Double(translation.width / (abs(diffX) * 0.5))
                    : clampedStart.panX
                let nextPanY: Double = abs(diffY) > 1
                    ? clampedStart.panY + (diffY >= 0 ? -1.0 : 1.0) * Double(translation.height / (abs(diffY) * 0.5))
                    : clampedStart.panY
                return WallpaperFraming(scale: clampedStart.scale, panX: nextPanX, panY: nextPanY, displayMode: .fit).clamped()
                
            case .center:
                let drawW = imageSize.width * baseScale * CGFloat(clampedStart.scale)
                let drawH = imageSize.height * baseScale * CGFloat(clampedStart.scale)
                let travelX = max(abs(drawW - viewportSize.width) * 0.5, (drawW + viewportSize.width) * 0.32)
                let travelY = max(abs(drawH - viewportSize.height) * 0.5, (drawH + viewportSize.height) * 0.32)
                let nextPanX = travelX > 1 ? clampedStart.panX - Double(translation.width / travelX) : clampedStart.panX
                let nextPanY = travelY > 1 ? clampedStart.panY - Double(translation.height / travelY) : clampedStart.panY
                return WallpaperFraming(scale: clampedStart.scale, panX: nextPanX, panY: nextPanY, displayMode: .center).clamped()
        }
    }
    
    
    nonisolated static func mediaLibraryWallpaperID(for assetID: String) -> String {
        "lib-\(assetID)"
    }
    
    
    /// Saves a user-chosen file URL into App Support with EXIF orientation normalization, adds it to the catalog, and activates it.
    @discardableResult
    func saveCustomWallpaper(from url: URL, title: String? = nil) -> WallpaperItem? {
        let resolvedTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        if let normalized = Self.downsampledImage(from: url, maxPixelSize: 2400) {
            return self.saveCustomWallpaper(normalized, title: resolvedTitle)
        }
        guard let fallback = NSImage(contentsOf: url) else { return nil }
        return self.saveCustomWallpaper(fallback, title: resolvedTitle)
    }
    
    
    /// Selects (or imports once without duplicating) a background asset from `UserMediaLibraryStore` as the active editor wallpaper.
    @discardableResult
    func selectMediaLibraryBackground(assetID: String, title: String, fileURL: URL) -> WallpaperItem? {
        let wallpaperID = Self.mediaLibraryWallpaperID(for: assetID)
        if let existing = self.allItems.first(where: { $0.id == wallpaperID }) {
            self.selectWallpaper(id: existing.id, enableIfDisabled: true)
            return existing
        }
        if let normalized = Self.downsampledImage(from: fileURL, maxPixelSize: 2400) ?? NSImage(contentsOf: fileURL) {
            return self.storeCustomWallpaper(normalized, customID: wallpaperID, title: title)
        }
        return nil
    }
    
    
    /// Re-bakes a cached Media Library wallpaper file after the user edits/crops it in the Material Library.
    @discardableResult
    func refreshMediaLibraryBackground(assetID: String, title: String, fileURL: URL) -> WallpaperItem? {
        let wallpaperID = Self.mediaLibraryWallpaperID(for: assetID)
        guard let normalized = Self.downsampledImage(from: fileURL, maxPixelSize: 2400) ?? NSImage(contentsOf: fileURL) else {
            return nil
        }
        self.rawImageCache.removeObject(forKey: wallpaperID as NSString)
        self.thumbnailCache.removeObject(forKey: wallpaperID as NSString)
        self.blurredImageCache.removeAllObjects()
        let wasSelected = (self.spec.selectedID == wallpaperID)
        let item = self.storeCustomWallpaper(normalized, customID: wallpaperID, title: title, activateAfter: wasSelected)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        return item
    }
    
    
    /// Saves a user-chosen artwork image into App Support, adds it to the catalog, and activates it.
    @discardableResult
    func saveCustomWallpaper(_ image: NSImage, title: String? = nil) -> WallpaperItem? {
        let id = "custom-\(UUID().uuidString.prefix(8).lowercased())"
        return self.storeCustomWallpaper(image, customID: id, title: title)
    }
    
    
    @discardableResult
    private func storeCustomWallpaper(_ image: NSImage, customID: String, title: String?, activateAfter: Bool = true) -> WallpaperItem? {
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                ?? image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
        else {
            return nil
        }
        let maxSide: CGFloat = 2400
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let scale = min(1.0, maxSide / max(1, max(w, h)))
        let targetSize = NSSize(width: max(64, (w * scale).rounded()), height: max(64, (h * scale).rounded()))
        
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = targetSize
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        
        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else {
            return nil
        }
        
        try? FileManager.default.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
        let filename = "\(customID).jpg"
        let fileURL = self.storageDirectory.appending(path: filename)
        do {
            try jpegData.write(to: fileURL, options: .atomic)
        } catch {
            return nil
        }
        
        let resolvedTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "自定义壁纸 \(self.customRecords.count + 1)"
        let record = WallpaperCustomRecord(id: customID, title: resolvedTitle, filename: filename, createdAt: Date())
        self.customRecords.removeAll { $0.id == customID }
        self.customRecords.append(record)
        self.persistCustomCatalog()
        
        if let cachedImg = NSImage(data: jpegData) {
            self.rawImageCache.setObject(cachedImg, forKey: customID as NSString, cost: Self.estimatedImageCost(cachedImg))
        }
        self.catalogVersion += 1
        if activateAfter {
            self.selectWallpaper(id: customID, enableIfDisabled: true)
        }
        return self.allItems.first { $0.id == customID }
    }
    
    
    func deleteCustomWallpaper(id: String) {
        guard let idx = self.customRecords.firstIndex(where: { $0.id == id }) else { return }
        let removed = self.customRecords.remove(at: idx)
        let url = self.storageDirectory.appending(path: removed.filename)
        try? FileManager.default.removeItem(at: url)
        self.rawImageCache.removeObject(forKey: id as NSString)
        self.thumbnailCache.removeObject(forKey: id as NSString)
        self.blurredImageCache.removeAllObjects()
        self.persistCustomCatalog()
        self.catalogVersion += 1
        
        if self.spec.selectedID == id {
            var next = self.spec
            next.perItemFraming.removeValue(forKey: id)
            let fallbackID = Self.builtInItems.first?.id ?? "ink-aurora"
            let restored = next.perItemFraming[fallbackID]?.clamped() ?? WallpaperFraming()
            next.selectedID = fallbackID
            next.scale = restored.scale
            next.panX = restored.panX
            next.panY = restored.panY
            next.displayMode = restored.displayMode
            self.spec = next
        } else {
            self.spec.perItemFraming.removeValue(forKey: id)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }
    
    
    /// Returns a lightweight cached `192×128` thumbnail for zero-lag Settings gallery scrolling.
    func thumbnailImage(for id: String) -> NSImage {
        if let cached = self.thumbnailCache.object(forKey: id as NSString) {
            return cached
        }
        let targetSize = NSSize(width: 192, height: 128)
        if let record = self.customRecords.first(where: { $0.id == id }) {
            let url = self.storageDirectory.appending(path: record.filename)
            if let source = self.rawImageCache.object(forKey: id as NSString) ?? Self.downsampledImage(from: url, maxPixelSize: 384) {
                let thumb = Self.downsample(source, to: targetSize)
                self.thumbnailCache.setObject(thumb, forKey: id as NSString, cost: Self.estimatedImageCost(thumb))
                return thumb
            }
        }
        let item = Self.builtInItems.first(where: { $0.id == id }) ?? Self.builtInItems[0]
        let rendered = Self.renderProceduralArtwork(item: item, size: targetSize)
        self.thumbnailCache.setObject(rendered, forKey: id as NSString, cost: Self.estimatedImageCost(rendered))
        return rendered
    }
    
    
    /// Returns the sharp preview/thumbnail artwork for the editor preview or card cover.
    func artworkImage(for id: String) -> NSImage {
        if let cached = self.rawImageCache.object(forKey: id as NSString) {
            return cached
        }
        if let record = self.customRecords.first(where: { $0.id == id }) {
            let url = self.storageDirectory.appending(path: record.filename)
            if let img = Self.downsampledImage(from: url, maxPixelSize: 2048) ?? NSImage(contentsOf: url) {
                self.rawImageCache.setObject(img, forKey: id as NSString, cost: Self.estimatedImageCost(img))
                return img
            }
        }
        let item = Self.builtInItems.first(where: { $0.id == id }) ?? Self.builtInItems[0]
        let rendered = Self.renderProceduralArtwork(item: item, size: NSSize(width: 640, height: 420))
        self.rawImageCache.setObject(rendered, forKey: id as NSString, cost: Self.estimatedImageCost(rendered))
        return rendered
    }
    
    
    /// Returns a cached pre-blurred backdrop image for zero-lag editor window compositing.
    func activeBackdropImage() -> NSImage? {
        guard self.spec.isEnabled else { return nil }
        let raw = self.artworkImage(for: self.spec.selectedID)
        // Quantize blur radius to 2px steps so continuous slider dragging stays silky 120fps.
        let quantizedBlur = Int((self.spec.blurRadius / 2.0).rounded()) * 2
        guard quantizedBlur >= 2 else { return raw }
        
        let cacheKey = "\(self.spec.selectedID)|\(quantizedBlur)" as NSString
        if let cached = self.blurredImageCache.object(forKey: cacheKey) {
            return cached
        }
        // Downsample large custom wallpapers to max 640px before Gaussian blur so GPU pass is instantaneous.
        let blurInput = Self.downsample(raw, maxSide: 640)
        guard let cg = blurInput.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return raw
        }
        let ciInput = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return raw }
        let scaledRadius = Double(quantizedBlur) * (Double(cg.width) / max(Double(raw.size.width), Double(cg.width), 1.0))
        filter.setValue(ciInput.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(max(1.0, scaledRadius), forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: ciInput.extent),
              let outCG = self.ciContext.createCGImage(output, from: ciInput.extent)
        else { return raw }
        
        let blurred = NSImage(cgImage: outCG, size: blurInput.size)
        self.blurredImageCache.setObject(blurred, forKey: cacheKey, cost: Self.estimatedImageCost(blurred))
        return blurred
    }
    
    
    private static func downsample(_ image: NSImage, to targetSize: NSSize) -> NSImage {
        let out = NSImage(size: targetSize, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .medium
            let src = image.size
            let scale = max(rect.width / max(1, src.width), rect.height / max(1, src.height))
            let drawW = src.width * scale
            let drawH = src.height * scale
            let drawRect = NSRect(x: (rect.width - drawW) * 0.5, y: (rect.height - drawH) * 0.5, width: drawW, height: drawH)
            image.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
            return true
        }
        return out
    }
    
    
    private static func downsample(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let src = image.size
        let longest = max(src.width, src.height)
        guard longest > maxSide else { return image }
        let ratio = maxSide / longest
        return self.downsample(image, to: NSSize(width: (src.width * ratio).rounded(), height: (src.height * ratio).rounded()))
    }
    
    
    private func clearTransientImageCaches() {
        self.rawImageCache.removeAllObjects()
        self.blurredImageCache.removeAllObjects()
    }
    
    
    private func shouldDebouncePersist(from oldSpec: WallpaperSpec, to newSpec: WallpaperSpec) -> Bool {
        guard self.database === CotLocalDatabase.shared, !CotLocalDatabase.isRunningUnitTests else {
            return false
        }
        return oldSpec.selectedID == newSpec.selectedID && oldSpec.isEnabled == newSpec.isEnabled
    }
    
    
    private func scheduleDebouncedPersistSpec() {
        self.persistDebounceTask?.cancel()
        self.persistDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.persistSpecImmediately()
        }
    }
    
    
    private static func downsampledImage(from url: URL, maxPixelSize: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
    
    
    private static func estimatedImageCost(_ image: NSImage) -> Int {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return max(4096, cg.bytesPerRow * cg.height)
        }
        return max(4096, Int(image.size.width * image.size.height * 16))
    }
    
    
    private func persistSpecImmediately() {
        guard let data = try? JSONEncoder().encode(self.spec),
              let json = String(data: data, encoding: .utf8)
        else { return }
        self.database.set(json, forKey: CotLocalDatabase.ConfigKey.editorWallpaperSpecJSON)
    }
    
    
    private func persistCustomCatalog() {
        guard let data = try? JSONEncoder().encode(self.customRecords),
              let json = String(data: data, encoding: .utf8)
        else { return }
        self.database.set(json, forKey: CotLocalDatabase.ConfigKey.editorWallpaperCustomCatalogJSON)
    }
    
    
    private static func renderProceduralArtwork(item: WallpaperItem, size: NSSize) -> NSImage {
        let colors = item.paletteHexes.map { NSColor(Color(hexString: $0)).usingColorSpace(.sRGB) ?? .black }
        let c0 = colors[safe: 0] ?? .black
        let c1 = colors[safe: 1] ?? .darkGray
        let c2 = colors[safe: 2] ?? .controlAccentColor
        
        let image = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.shouldAntialias = true
            let bgGrad = NSGradient(colors: [c0, c1, c0])
            bgGrad?.draw(in: rect, angle: 34)
            
            // Luminous primary & secondary atmospheric clouds
            let glow1 = NSGradient(colors: [c2.withAlphaComponent(0.75), c2.withAlphaComponent(0.22), c2.withAlphaComponent(0)])
            glow1?.draw(
                in: NSBezierPath(ovalIn: NSRect(x: rect.width * 0.14, y: rect.height * 0.22, width: rect.width * 0.72, height: rect.height * 0.72)),
                relativeCenterPosition: NSPoint(x: -0.15, y: 0.2)
            )
            
            let glow2 = NSGradient(colors: [c1.blended(withFraction: 0.45, of: .white)?.withAlphaComponent(0.45) ?? c2.withAlphaComponent(0.35), c1.withAlphaComponent(0)])
            glow2?.draw(
                in: NSBezierPath(ovalIn: NSRect(x: -rect.width * 0.12, y: -rect.height * 0.10, width: rect.width * 0.68, height: rect.height * 0.68)),
                relativeCenterPosition: NSPoint(x: 0.25, y: -0.25)
            )
            
            // Architectural horizon arcs unique per theme ID
            let seed = abs(item.id.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) })
            let ringCount = 5
            for idx in 0..<ringCount {
                let frac = CGFloat(idx + 1) / CGFloat(ringCount + 1)
                let radius = min(rect.width, rect.height) * (0.20 + frac * 0.44)
                let cx = rect.width * (0.48 + CGFloat((seed + idx * 17) % 14 - 7) * 0.015)
                let cy = rect.height * (0.50 + CGFloat((seed + idx * 23) % 14 - 7) * 0.015)
                let ring = NSBezierPath(ovalIn: NSRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
                ring.lineWidth = idx == 2 ? 2.4 : 1.1
                c2.withAlphaComponent(0.26 - Double(idx) * 0.035).setStroke()
                ring.stroke()
            }
            
            // Subtle architectural dot grid for editorial depth
            c2.withAlphaComponent(0.14).setFill()
            let step: CGFloat = 28
            var y: CGFloat = 18
            while y < rect.height {
                var x: CGFloat = 18
                while x < rect.width {
                    NSBezierPath(ovalIn: NSRect(x: x - 1, y: y - 1, width: 2, height: 2)).fill()
                    x += step
                }
                y += step
            }
            return true
        }
        return image
    }
}
