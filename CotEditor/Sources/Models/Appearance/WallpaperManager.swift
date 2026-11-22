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
import Observation
import SwiftUI

nonisolated struct WallpaperSpec: Codable, Equatable, Sendable {
    
    var isEnabled: Bool = false
    var selectedID: String = "ink-aurora"
    var opacity: Double = 0.16      // 0.04 ... 0.55
    var blurRadius: Double = 10.0   // 0.0 ... 32.0
    
    static let `default` = WallpaperSpec()
    
    func clamped() -> WallpaperSpec {
        var copy = self
        copy.opacity = max(0.04, min(0.55, self.opacity))
        copy.blurRadius = max(0.0, min(32.0, self.blurRadius))
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
            let normalized = self.spec.clamped()
            if normalized != self.spec {
                self.spec = normalized
                return
            }
            self.persistSpec()
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }
    
    private(set) var customRecords: [WallpaperCustomRecord] = []
    private(set) var catalogVersion: Int = 0
    
    private let database: CotLocalDatabase
    private let storageDirectory: URL
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var rawImageCache: [String: NSImage] = [:]
    private var thumbnailCache: [String: NSImage] = [:]
    private var blurredImageCache: [String: NSImage] = [:]
    
    
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
        self.rawImageCache.removeAll()
        self.thumbnailCache.removeAll()
        self.blurredImageCache.removeAll()
        self.catalogVersion += 1
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
    
    
    /// Selects a wallpaper by ID and automatically enables wallpaper backdrop.
    func selectWallpaper(id: String, enableIfDisabled: Bool = true) {
        var next = self.spec
        next.selectedID = id
        if enableIfDisabled {
            next.isEnabled = true
        }
        self.spec = next
    }
    
    
    /// Saves a user-chosen artwork image into App Support, adds it to the catalog, and activates it.
    @discardableResult
    func saveCustomWallpaper(_ image: NSImage, title: String? = nil) -> WallpaperItem? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let maxSide: CGFloat = 1920
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
        let id = "custom-\(UUID().uuidString.prefix(8).lowercased())"
        let filename = "\(id).jpg"
        let fileURL = self.storageDirectory.appending(path: filename)
        do {
            try jpegData.write(to: fileURL, options: .atomic)
        } catch {
            return nil
        }
        
        let resolvedTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "自定义壁纸 \(self.customRecords.count + 1)"
        let record = WallpaperCustomRecord(id: id, title: resolvedTitle, filename: filename, createdAt: Date())
        self.customRecords.append(record)
        self.persistCustomCatalog()
        
        if let cachedImg = NSImage(data: jpegData) {
            self.rawImageCache[id] = cachedImg
        }
        self.catalogVersion += 1
        self.selectWallpaper(id: id, enableIfDisabled: true)
        return self.allItems.first { $0.id == id }
    }
    
    
    func deleteCustomWallpaper(id: String) {
        guard let idx = self.customRecords.firstIndex(where: { $0.id == id }) else { return }
        let removed = self.customRecords.remove(at: idx)
        let url = self.storageDirectory.appending(path: removed.filename)
        try? FileManager.default.removeItem(at: url)
        self.rawImageCache.removeValue(forKey: id)
        self.thumbnailCache.removeValue(forKey: id)
        self.blurredImageCache.keys.filter { $0.hasPrefix("\(id)|") }.forEach { self.blurredImageCache.removeValue(forKey: $0) }
        self.persistCustomCatalog()
        self.catalogVersion += 1
        
        if self.spec.selectedID == id {
            var next = self.spec
            next.selectedID = Self.builtInItems.first?.id ?? "ink-aurora"
            self.spec = next
        } else {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }
    
    
    /// Returns a lightweight cached `192×128` thumbnail for zero-lag Settings gallery scrolling.
    func thumbnailImage(for id: String) -> NSImage {
        if let cached = self.thumbnailCache[id] {
            return cached
        }
        let targetSize = NSSize(width: 192, height: 128)
        if let record = self.customRecords.first(where: { $0.id == id }) {
            let url = self.storageDirectory.appending(path: record.filename)
            if let source = self.rawImageCache[id] ?? NSImage(contentsOf: url) {
                let thumb = Self.downsample(source, to: targetSize)
                self.thumbnailCache[id] = thumb
                return thumb
            }
        }
        let item = Self.builtInItems.first(where: { $0.id == id }) ?? Self.builtInItems[0]
        let rendered = Self.renderProceduralArtwork(item: item, size: targetSize)
        self.thumbnailCache[id] = rendered
        return rendered
    }
    
    
    /// Returns the sharp preview/thumbnail artwork for the editor preview or card cover.
    func artworkImage(for id: String) -> NSImage {
        if let cached = self.rawImageCache[id] {
            return cached
        }
        if let record = self.customRecords.first(where: { $0.id == id }) {
            let url = self.storageDirectory.appending(path: record.filename)
            if let img = NSImage(contentsOf: url) {
                self.rawImageCache[id] = img
                return img
            }
        }
        let item = Self.builtInItems.first(where: { $0.id == id }) ?? Self.builtInItems[0]
        let rendered = Self.renderProceduralArtwork(item: item, size: NSSize(width: 640, height: 420))
        self.rawImageCache[id] = rendered
        return rendered
    }
    
    
    /// Returns a cached pre-blurred backdrop image for zero-lag editor window compositing.
    func activeBackdropImage() -> NSImage? {
        guard self.spec.isEnabled else { return nil }
        let raw = self.artworkImage(for: self.spec.selectedID)
        // Quantize blur radius to 2px steps so continuous slider dragging stays silky 120fps.
        let quantizedBlur = Int((self.spec.blurRadius / 2.0).rounded()) * 2
        guard quantizedBlur >= 2 else { return raw }
        
        let cacheKey = "\(self.spec.selectedID)|\(quantizedBlur)"
        if let cached = self.blurredImageCache[cacheKey] {
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
        if self.blurredImageCache.count > 24 {
            self.blurredImageCache.removeAll()
        }
        self.blurredImageCache[cacheKey] = blurred
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
    
    
    private func persistSpec() {
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
