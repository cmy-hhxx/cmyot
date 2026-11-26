//
//  PlainTextInlineImageStore.swift
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
import UniformTypeIdentifiers

/// Stepless user customization transform (zoom, free X/Y offset, rotation, or explicit pixel size) for an inline image.
nonisolated struct InlineImageTransform: Codable, Equatable, Sendable {
    
    var scale: CGFloat = 1.0          // 0.15 ... 4.0 (stepless)
    var offsetX: CGFloat = 0.0        // Horizontal offset inside editor canvas
    var offsetY: CGFloat = 0.0        // Extra top padding (0 ... 240)
    var rotationDegrees: CGFloat = 0  // Stepless angle (-180 ... +180)
    var customWidth: CGFloat? = nil   // Explicit bounding-box width (>= 64pt)
    var customHeight: CGFloat? = nil  // Explicit bounding-box height (>= 48pt)
    
    var isIdentity: Bool {
        abs(self.scale - 1.0) < 0.001 &&
        abs(self.offsetX) < 0.5 &&
        abs(self.offsetY) < 0.5 &&
        abs(self.rotationDegrees) < 0.1 &&
        self.customWidth == nil &&
        self.customHeight == nil
    }
    
    static let identity = InlineImageTransform()
    
    func clamped() -> InlineImageTransform {
        var copy = self
        copy.scale = max(0.15, min(4.0, self.scale))
        copy.offsetX = max(-1200, min(1200, self.offsetX))
        copy.offsetY = max(0, min(240, self.offsetY))
        var deg = self.rotationDegrees.truncatingRemainder(dividingBy: 360)
        if deg > 180 { deg -= 360 }
        if deg < -180 { deg += 360 }
        copy.rotationDegrees = deg
        if let w = self.customWidth {
            copy.customWidth = max(64, min(2400, round(w)))
        }
        if let h = self.customHeight {
            copy.customHeight = max(48, min(2400, round(h)))
        }
        return copy
    }
}


/// Computed unrotated image draw size, rotated bounding box, and card size for layout & drawing.
nonisolated struct InlineImageDisplayGeometry: Equatable, Sendable {
    
    let drawSize: NSSize
    let rotatedBoxSize: NSSize
    let cardSize: NSSize
    let transform: InlineImageTransform
}


/// Pure, deterministic stepless zoom geometry math shared across pinch, 8-handle drag, sliders, and layout.
nonisolated enum InlineImageZoomMath {
    
    static let minScaleFloor: CGFloat = 0.15
    static let maxScaleCeiling: CGFloat = 4.0
    static let maxCardHeight: CGFloat = 1600
    
    
    /// Computes the baseline `100%` display size before user transforms.
    static func baseDrawSize(
        naturalSize: NSSize,
        maxImageWidth: CGFloat = 460,
        maxImageHeight: CGFloat = 260
    ) -> NSSize {
        guard naturalSize.width > 0, naturalSize.height > 0 else {
            return NSSize(width: BoundingBoxResizeMath.minWidth, height: BoundingBoxResizeMath.minHeight)
        }
        let baseScale = min(maxImageWidth / naturalSize.width, maxImageHeight / naturalSize.height, 1.0)
        return NSSize(
            width: max(1, round(naturalSize.width * baseScale)),
            height: max(1, round(naturalSize.height * baseScale))
        )
    }
    
    
    /// Maximum usable horizontal width for an explicitly scaled inline image inside the editor container.
    static func canvasMaxWidth(containerWidth: CGFloat, maxImageWidth: CGFloat = 460) -> CGFloat {
        let finiteContainerW = (containerWidth.isFinite && containerWidth > 0 && containerWidth <= 100_000)
            ? containerWidth
            : maxImageWidth
        return max(maxImageWidth, max(160, finiteContainerW - 24))
    }
    
    
    /// Clamps `desiredWidth` strictly preserving `naturalSize` aspect ratio within usable width/height bounds.
    static func clampedAspectSize(
        desiredWidth: CGFloat,
        naturalSize: NSSize,
        maxWidth: CGFloat,
        maxHeight: CGFloat = InlineImageZoomMath.maxCardHeight
    ) -> NSSize {
        guard naturalSize.width > 0, naturalSize.height > 0 else {
            let safeW = max(BoundingBoxResizeMath.minWidth, min(maxWidth, round(desiredWidth)))
            return NSSize(width: safeW, height: BoundingBoxResizeMath.minHeight)
        }
        
        let aspect = naturalSize.width / naturalSize.height
        let safeMaxW = max(BoundingBoxResizeMath.minWidth, maxWidth)
        let safeMaxH = max(BoundingBoxResizeMath.minHeight, maxHeight)
        
        // Enforce aspect-safe minimum width without over-blocking ultra-wide banners.
        let minHeightFloor: CGFloat = aspect > 2.5 ? 28 : BoundingBoxResizeMath.minHeight
        let minWForMinH = min(safeMaxW, ceil(minHeightFloor * aspect))
        let effectiveMinW = min(safeMaxW, max(BoundingBoxResizeMath.minWidth, minWForMinH))
        let maxWForMaxH = max(effectiveMinW, floor(safeMaxH * aspect))
        let effectiveMaxW = max(effectiveMinW, min(safeMaxW, maxWForMaxH))
        
        let w = max(effectiveMinW, min(effectiveMaxW, round(desiredWidth)))
        let h = max(1, min(safeMaxH, round(w / aspect)))
        return NSSize(width: w, height: h)
    }
    
    
    /// Returns the exact reachable `[min, max]` scale range relative to `baseDrawSize`, eliminating slider dead zones.
    static func scaleBounds(
        naturalSize: NSSize,
        containerWidth: CGFloat,
        maxImageWidth: CGFloat = 460,
        maxImageHeight: CGFloat = 260
    ) -> ClosedRange<CGFloat> {
        let base = self.baseDrawSize(
            naturalSize: naturalSize,
            maxImageWidth: maxImageWidth,
            maxImageHeight: maxImageHeight
        )
        let canvasMaxW = self.canvasMaxWidth(containerWidth: containerWidth, maxImageWidth: maxImageWidth)
        let minSize = self.clampedAspectSize(
            desiredWidth: max(1, base.width * self.minScaleFloor),
            naturalSize: naturalSize,
            maxWidth: canvasMaxW
        )
        let maxSize = self.clampedAspectSize(
            desiredWidth: base.width * self.maxScaleCeiling,
            naturalSize: naturalSize,
            maxWidth: canvasMaxW
        )
        let lower = max(self.minScaleFloor, min(1.0, minSize.width / max(1, base.width)))
        let upper = max(max(lower + 0.05, 1.0), min(self.maxScaleCeiling, maxSize.width / max(1, base.width)))
        return lower...upper
    }
    
    
    /// Computes the true effective scale factor represented by `drawWidth` relative to baseline `100%`.
    static func effectiveScale(
        drawWidth: CGFloat,
        naturalSize: NSSize,
        maxImageWidth: CGFloat = 460,
        maxImageHeight: CGFloat = 260
    ) -> CGFloat {
        let base = self.baseDrawSize(
            naturalSize: naturalSize,
            maxImageWidth: maxImageWidth,
            maxImageHeight: maxImageHeight
        )
        let raw = drawWidth / max(1, base.width)
        return max(self.minScaleFloor, min(self.maxScaleCeiling, raw))
    }
    
    
    /// Produces a synchronized transform for an explicit target `scale` (keeping `scale`, `customWidth`, and `customHeight` aligned).
    static func transformForTargetScale(
        _ requestedScale: CGFloat,
        baseTransform: InlineImageTransform,
        naturalSize: NSSize,
        containerWidth: CGFloat,
        maxImageWidth: CGFloat = 460,
        maxImageHeight: CGFloat = 260
    ) -> InlineImageTransform {
        let base = self.baseDrawSize(
            naturalSize: naturalSize,
            maxImageWidth: maxImageWidth,
            maxImageHeight: maxImageHeight
        )
        let bounds = self.scaleBounds(
            naturalSize: naturalSize,
            containerWidth: containerWidth,
            maxImageWidth: maxImageWidth,
            maxImageHeight: maxImageHeight
        )
        let clampedScale = max(bounds.lowerBound, min(bounds.upperBound, requestedScale))
        let canvasMaxW = self.canvasMaxWidth(containerWidth: containerWidth, maxImageWidth: maxImageWidth)
        let prevSize = self.clampedAspectSize(
            desiredWidth: baseTransform.customWidth ?? (base.width * baseTransform.scale),
            naturalSize: naturalSize,
            maxWidth: canvasMaxW
        )
        let nextSize = self.clampedAspectSize(
            desiredWidth: base.width * clampedScale,
            naturalSize: naturalSize,
            maxWidth: canvasMaxW
        )
        let achievedScale = self.effectiveScale(
            drawWidth: nextSize.width,
            naturalSize: naturalSize,
            maxImageWidth: maxImageWidth,
            maxImageHeight: maxImageHeight
        )
        
        var updated = baseTransform
        if abs(achievedScale - 1.0) < 0.015 {
            updated.scale = 1.0
            updated.customWidth = nil
            updated.customHeight = nil
        } else {
            updated.scale = achievedScale
            updated.customWidth = nextSize.width
            updated.customHeight = nextSize.height
        }
        
        if nextSize.height < prevSize.height, updated.offsetY > 0 {
            let scaledOffset = updated.offsetY * (nextSize.height / max(1, prevSize.height))
            updated.offsetY = scaledOffset < 2 ? 0 : round(scaledOffset)
        }
        return updated.clamped()
    }
    
    
    /// Returns deduplicated quick-scale presets tailored to `bounds` so UI pills never repeat values.
    static func quickScalePresets(
        for bounds: ClosedRange<CGFloat>,
        fitLabel: String
    ) -> [(label: String, scale: CGFloat)] {
        var candidates: [(label: String, scale: CGFloat)] = []
        let standard: [CGFloat] = [0.5, 1.0, 1.5]
        for target in standard {
            let clamped = max(bounds.lowerBound, min(bounds.upperBound, target))
            let pct = Int((clamped * 100).rounded())
            if !candidates.contains(where: { abs($0.scale - clamped) < 0.04 }) {
                candidates.append(("\(pct)%", clamped))
            }
        }
        let fitScale = bounds.upperBound
        if !candidates.contains(where: { abs($0.scale - fitScale) < 0.04 }) {
            candidates.append((fitLabel, fitScale))
        } else if let idx = candidates.lastIndex(where: { abs($0.scale - fitScale) < 0.04 }), fitScale > 1.08 {
            candidates[idx] = (fitLabel, fitScale)
        }
        return candidates
    }
    
    
    /// Produces a synchronized, zero-dead-zone transform step for trackpad pinch magnification.
    static func transformForMagnify(
        current: InlineImageTransform,
        currentDrawSize: NSSize,
        naturalSize: NSSize,
        factor: CGFloat,
        containerWidth: CGFloat,
        maxImageWidth: CGFloat = 460,
        maxImageHeight: CGFloat = 260
    ) -> InlineImageTransform {
        let clampedFactor = max(0.5, min(2.0, factor))
        let base = self.baseDrawSize(
            naturalSize: naturalSize,
            maxImageWidth: maxImageWidth,
            maxImageHeight: maxImageHeight
        )
        let currentW = max(1, currentDrawSize.width > 0 ? currentDrawSize.width : (current.customWidth ?? base.width * current.scale))
        let targetScale = (currentW * clampedFactor) / max(1, base.width)
        return self.transformForTargetScale(
            targetScale,
            baseTransform: current,
            naturalSize: naturalSize,
            containerWidth: containerWidth,
            maxImageWidth: maxImageWidth,
            maxImageHeight: maxImageHeight
        )
    }
}


/// Manages images embedded inside Plain Text (`SyntaxName.none`) and Markdown documents.
///
/// The text file stays clean by storing a compact token `⟦🖼 <filename>⟧`
/// while the image file itself lives in a hidden `.cot-assets/` folder beside the document
/// (or in `~/Library/Application Support/Cot/InlineImages/` for untitled documents).
/// In the editor, `EditorTextView` and `LayoutManager` render a sleek inline card right under
/// the line containing the token, supporting stepless zoom, position offset, and rotation.
nonisolated final class PlainTextInlineImageStore: @unchecked Sendable {
    
    static let shared = PlainTextInlineImageStore()
    
    
    /// Returns whether inline image cards, drag-drop, and clipboard image paste are enabled for `syntaxName`.
    static func supportsInlineImages(syntaxName: String) -> Bool {
        let normalized = syntaxName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return syntaxName == SyntaxName.none
            || normalized.isEmpty
            || normalized == "plain text"
            || normalized == "none"
            || normalized == "markdown"
    }
    
    
    /// Fast, zero-decode metadata check used by context menus & UI validation (`< 0.05ms`).
    static func hasPasteableImage(in pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        if types.contains(where: { Self.imagePasteboardTypes.contains($0) }) {
            if let plainText = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !plainText.isEmpty
            {
                let html = pasteboard.string(forType: .html) ?? ""
                let looksLikeHTMLImage = html.localizedCaseInsensitiveContains("<img")
                let looksLikeSingleLineURLOrFilename = !plainText.contains("\n")
                    && (plainText.hasPrefix("http://") || plainText.hasPrefix("https://") || plainText.hasPrefix("file://")
                        || Self.imageExtensions.contains(URL(filePath: plainText).pathExtension.lowercased()))
                if !looksLikeHTMLImage && !looksLikeSingleLineURLOrFilename {
                    return false
                }
            }
            return true
        }
        if types.contains(.fileURL),
           let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           urls.contains(where: { Self.imageExtensions.contains($0.pathExtension.lowercased()) })
        {
            return true
        }
        return false
    }
    
    private static let tokenRegex = try! NSRegularExpression(pattern: "⟦🖼\\s*([^⟧]+?)⟧")
    private static let imagePasteboardTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.heic"),
        NSPasteboard.PasteboardType("com.compuserve.gif"),
        NSPasteboard.PasteboardType("org.webmproject.webp"),
    ]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "bmp"]
    
    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
    
    private let lock = NSLock()
    private let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
    private var missingImageKeys: Set<String> = []
    private var imageSizeCache: [String: NSSize] = [:]
    private var transformsByFolder: [String: [String: InlineImageTransform]] = [:]
    private let persistQueue = DispatchQueue(label: "com.coteditor.inline-image-transforms", qos: .utility)
    
    
    /// Extracts an image from the pasteboard for `Cmd+V` pasting, handling screenshots,
    /// browser/chat image copies (which often also place URL/HTML strings on the pasteboard),
    /// and copied image files from Finder.
    func extractImage(from pasteboard: NSPasteboard) -> NSImage? {
        
        // 1. Check copied image files (e.g. Cmd+C on a .png in Finder puts fileURL + filename string)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls where Self.imageExtensions.contains(url.pathExtension.lowercased()) {
                if let image = NSImage(contentsOf: url) {
                    return image
                }
            }
        }
        
        // 2. Check explicit raster image data types on the pasteboard
        let types = pasteboard.types ?? []
        let hasExplicitImageData = types.contains(where: { Self.imagePasteboardTypes.contains($0) })
        guard hasExplicitImageData else { return nil }
        
        // If there is multi-line plain text AND no HTML <img> tag, assume the user copied rich text
        // (e.g. a document excerpt) rather than an image.
        if let plainText = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !plainText.isEmpty
        {
            let html = pasteboard.string(forType: .html) ?? ""
            let looksLikeHTMLImage = html.localizedCaseInsensitiveContains("<img")
            let looksLikeSingleLineURLOrFilename = !plainText.contains("\n")
                && (plainText.hasPrefix("http://") || plainText.hasPrefix("https://") || plainText.hasPrefix("file://")
                    || Self.imageExtensions.contains(URL(filePath: plainText).pathExtension.lowercased()))
            
            if !looksLikeHTMLImage && !looksLikeSingleLineURLOrFilename {
                return nil
            }
        }
        
        for type in Self.imagePasteboardTypes {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) {
                return image
            }
        }
        
        return NSImage(pasteboard: pasteboard)
    }
    
    
    /// Stores a pasted or dropped `NSImage` for a document and returns the plain-text token to insert.
    func store(image: NSImage, for documentURL: URL?) -> (token: String, fileURL: URL)? {
        
        guard let encoded = Self.encodePNGPayload(from: image) else { return nil }
        
        let stamp = Self.filenameDateFormatter.string(from: Date())
        let shortID = String(UUID().uuidString.prefix(4)).lowercased()
        let filename = "img-\(stamp)-\(shortID).png"
        
        let folder = self.assetsFolder(for: documentURL)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        
        let targetURL = folder.appending(path: filename)
        do {
            try encoded.data.write(to: targetURL, options: .atomic)
        } catch {
            return nil
        }
        
        let key = self.cacheKey(for: filename, documentURL: documentURL)
        self.lock.withLock {
            self.missingImageKeys.remove(key)
            let cost = Self.estimatedByteCost(for: encoded.renderedImage, logicalSize: encoded.logicalSize)
            self.imageCache.setObject(encoded.renderedImage, forKey: key as NSString, cost: cost)
            self.imageSizeCache[key] = encoded.logicalSize
        }
        
        return ("⟦🖼 \(filename)⟧", targetURL)
    }
    
    
    /// Copies an existing dropped image file into the assets store and returns the token.
    func storeImageFile(at sourceURL: URL, for documentURL: URL?) -> (token: String, fileURL: URL)? {
        
        guard let image = NSImage(contentsOf: sourceURL) else { return nil }
        return self.store(image: image, for: documentURL)
    }
    
    
    /// Copies any inline images referenced in `text` from the global untitled cache into the saved
    /// document's `.cot-assets/` folder so the saved file stays self-contained.
    func migrateGlobalAssetsIfNeeded(in text: String, to documentURL: URL) {
        
        let nsString = text as NSString
        let tokens = self.findTokens(in: nsString, range: NSRange(location: 0, length: nsString.length))
        guard !tokens.isEmpty else { return }
        
        let globalFolder = self.assetsFolder(for: nil)
        let docFolder = self.assetsFolder(for: documentURL)
        
        for token in tokens {
            let sourceURL = globalFolder.appending(path: token.identifier)
            let destURL = docFolder.appending(path: token.identifier)
            if FileManager.default.fileExists(atPath: sourceURL.path),
               !FileManager.default.fileExists(atPath: destURL.path)
            {
                try? FileManager.default.createDirectory(at: docFolder, withIntermediateDirectories: true)
                try? FileManager.default.copyItem(at: sourceURL, to: destURL)
            }
            
            let destKey = self.cacheKey(for: token.identifier, documentURL: documentURL)
            self.lock.withLock {
                self.missingImageKeys.remove(destKey)
            }
            
            let globalTransform = self.transform(for: token.identifier, documentURL: nil)
            if !globalTransform.isIdentity {
                self.setTransform(globalTransform, for: token.identifier, documentURL: documentURL)
            }
        }
    }
    
    
    /// Finds all inline image tokens inside the given `NSString` range.
    func findTokens(in string: NSString, range: NSRange) -> [(range: NSRange, identifier: String)] {
        
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: string.length))
        guard safeRange.length >= 4 else { return [] }
        // Fast literal scan avoids NSString -> String bridging & regex work on normal text lines.
        guard string.range(of: "⟦🖼", options: .literal, range: safeRange).location != NSNotFound else {
            return []
        }
        
        let slice = string.substring(with: safeRange)
        let nsSlice = slice as NSString
        return Self.tokenRegex.matches(in: slice, range: NSRange(location: 0, length: nsSlice.length)).compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            let identifier = nsSlice.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let globalRange = NSRange(location: safeRange.location + match.range.location, length: match.range.length)
            return (globalRange, identifier)
        }
    }
    
    
    /// Resolves and caches the `NSImage` for a token identifier scoped strictly to `documentURL`.
    func image(for identifier: String, documentURL: URL?) -> NSImage? {
        
        let cacheKey = self.cacheKey(for: identifier, documentURL: documentURL)
        let cachedState: (image: NSImage?, isKnownMissing: Bool) = self.lock.withLock {
            (self.imageCache.object(forKey: cacheKey as NSString), self.missingImageKeys.contains(cacheKey))
        }
        if let cached = cachedState.image {
            return cached
        }
        if cachedState.isKnownMissing {
            return nil
        }
        
        if let url = self.imageURL(for: identifier, documentURL: documentURL),
           let loaded = NSImage(contentsOf: url)
        {
            let logicalSize = Self.naturalImageSize(for: loaded)
            let cost = Self.estimatedByteCost(for: loaded, logicalSize: logicalSize)
            self.lock.withLock {
                self.missingImageKeys.remove(cacheKey)
                self.imageCache.setObject(loaded, forKey: cacheKey as NSString, cost: cost)
                self.imageSizeCache[cacheKey] = logicalSize
            }
            return loaded
        }
        
        self.lock.withLock {
            if self.missingImageKeys.count >= 512 {
                self.missingImageKeys.removeAll(keepingCapacity: true)
            }
            self.missingImageKeys.insert(cacheKey)
        }
        return nil
    }
    
    
    /// Computes the true logical display size of an image while strictly preserving its pixel aspect ratio.
    static func naturalImageSize(for image: NSImage) -> NSSize {
        
        let bitmaps = image.representations.compactMap { $0 as? NSBitmapImageRep }
        if let rep = bitmaps.max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }),
           rep.pixelsWide > 0, rep.pixelsHigh > 0
        {
            return Self.logicalSize(pixelWidth: rep.pixelsWide, pixelHeight: rep.pixelsHigh, hintedSize: image.size)
        }
        
        var proposed = NSRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
           cgImage.width > 0, cgImage.height > 0
        {
            return Self.logicalSize(pixelWidth: cgImage.width, pixelHeight: cgImage.height, hintedSize: image.size)
        }
        
        return image.size
    }
    
    
    private static func logicalSize(pixelWidth: Int, pixelHeight: Int, hintedSize: NSSize) -> NSSize {
        
        let pxW = CGFloat(pixelWidth)
        let pxH = CGFloat(pixelHeight)
        let aspectRatio = pxW / pxH
        
        let logicalWidth: CGFloat
        if hintedSize.width > 0 {
            let density = pxW / hintedSize.width
            if abs(density - 2.0) < 0.15 {
                logicalWidth = pxW / 2.0
            } else if abs(density - 3.0) < 0.15 {
                logicalWidth = pxW / 3.0
            } else if density >= 0.85 && density <= 1.15 {
                logicalWidth = pxW > 960 ? pxW / 2.0 : pxW
            } else {
                logicalWidth = hintedSize.width
            }
        } else {
            logicalWidth = pxW > 960 ? pxW / 2.0 : pxW
        }
        
        let logicalHeight = logicalWidth / aspectRatio
        return NSSize(width: logicalWidth, height: logicalHeight)
    }
    
    
    /// Computes the maximum image width allowed inside a text container at `glyphX`.
    static func effectiveMaxImageWidth(containerWidth: CGFloat, glyphX: CGFloat = 0) -> CGFloat {
        
        let usable = containerWidth - glyphX - 24
        if usable.isFinite && usable > 0 {
            return min(460, max(120, usable))
        }
        return 460
    }
    
    
    /// Returns the persisted stepless transform for an image token, defaulting to `.identity`.
    func transform(for identifier: String, documentURL: URL?) -> InlineImageTransform {
        
        let folder = self.assetsFolder(for: documentURL)
        let folderKey = folder.path
        return self.lock.withLock {
            if let cachedMap = self.transformsByFolder[folderKey] {
                return cachedMap[identifier] ?? .identity
            }
            let loaded = self.loadTransformMap(in: folder)
            self.transformsByFolder[folderKey] = loaded
            return loaded[identifier] ?? .identity
        }
    }
    
    
    /// Persists a stepless transform (scale, offsetX/Y, rotation) for an image token.
    /// Pass `persist: false` during high-frequency live drag/pinch frames to avoid redundant disk writes,
    /// then flush once with `persist: true` on gesture end.
    func setTransform(
        _ transform: InlineImageTransform,
        for identifier: String,
        documentURL: URL?,
        persist: Bool = true
    ) {
        
        let clamped = transform.clamped()
        let folder = self.assetsFolder(for: documentURL)
        let folderKey = folder.path
        
        let updatedMap: [String: InlineImageTransform] = self.lock.withLock {
            var map = self.transformsByFolder[folderKey] ?? self.loadTransformMap(in: folder)
            if clamped.isIdentity {
                map.removeValue(forKey: identifier)
            } else {
                map[identifier] = clamped
            }
            self.transformsByFolder[folderKey] = map
            return map
        }
        guard persist else { return }
        // Serialize disk writes off the main thread so 120Hz live resize/drag never stalls UI.
        self.persistQueue.async {
            Self.writeTransformMap(updatedMap, in: folder)
        }
    }
    
    
    func resetTransform(for identifier: String, documentURL: URL?) {
        self.setTransform(.identity, for: identifier, documentURL: documentURL)
    }
    
    
    /// Returns the cached or computed logical display size (preserving natural pixel aspect ratio) for `identifier`.
    func naturalSize(for identifier: String, documentURL: URL?) -> NSSize? {
        let cacheKey = self.cacheKey(for: identifier, documentURL: documentURL)
        if let cached = self.lock.withLock({ self.imageSizeCache[cacheKey] }) {
            return cached
        }
        if let img = self.image(for: identifier, documentURL: documentURL) {
            return Self.naturalImageSize(for: img)
        }
        return nil
    }
    
    
    /// Computes complete display geometry accounting for stepless scale, rotation bounding box, and spacing.
    func displayGeometry(
        for identifier: String,
        documentURL: URL?,
        containerWidth: CGFloat,
        maxImageWidth: CGFloat = 460,
        maxImageHeight: CGFloat = 260
    ) -> InlineImageDisplayGeometry? {
        
        guard let imgSize = self.naturalSize(for: identifier, documentURL: documentURL),
              imgSize.width > 0, imgSize.height > 0
        else { return nil }
        
        let base = InlineImageZoomMath.baseDrawSize(
            naturalSize: imgSize,
            maxImageWidth: maxImageWidth,
            maxImageHeight: maxImageHeight
        )
        let transform = self.transform(for: identifier, documentURL: documentURL)
        
        if transform.isIdentity {
            return InlineImageDisplayGeometry(
                drawSize: base,
                rotatedBoxSize: base,
                cardSize: NSSize(width: base.width + 8, height: base.height + 8),
                transform: .identity
            )
        }
        
        // When user explicitly resizes or scales (> 1.0), break past the 460pt thumbnail cap up to full editor canvas width.
        let canvasMaxW = InlineImageZoomMath.canvasMaxWidth(containerWidth: containerWidth, maxImageWidth: maxImageWidth)
        let aspect = imgSize.width / imgSize.height
        let desiredW: CGFloat
        if let customW = transform.customWidth {
            desiredW = customW
        } else if let customH = transform.customHeight {
            desiredW = customH * aspect
        } else {
            desiredW = base.width * transform.scale
        }
        let clamped = InlineImageZoomMath.clampedAspectSize(
            desiredWidth: desiredW,
            naturalSize: imgSize,
            maxWidth: canvasMaxW
        )
        let clampedW = clamped.width
        let clampedH = clamped.height
        
        let rad = abs(transform.rotationDegrees) * .pi / 180.0
        let cosA = abs(cos(rad))
        let sinA = abs(sin(rad))
        let rotW = ceil(clampedW * cosA + clampedH * sinA)
        let rotH = ceil(clampedW * sinA + clampedH * cosA)
        let extraTop = max(0, transform.offsetY)
        
        return InlineImageDisplayGeometry(
            drawSize: NSSize(width: clampedW, height: clampedH),
            rotatedBoxSize: NSSize(width: rotW, height: rotH),
            cardSize: NSSize(width: rotW + 8, height: rotH + 8 + extraTop),
            transform: transform
        )
    }
    
    
    /// Returns the scaled card size (including padding) for an inline image token, or `nil` if unresolved.
    func cardSize(
        for identifier: String,
        documentURL: URL?,
        maxImageWidth: CGFloat = 460,
        maxImageHeight: CGFloat = 260,
        containerWidth: CGFloat? = nil
    ) -> NSSize? {
        
        let resolvedContainer = containerWidth ?? maxImageWidth
        return self.displayGeometry(
            for: identifier,
            documentURL: documentURL,
            containerWidth: resolvedContainer,
            maxImageWidth: maxImageWidth,
            maxImageHeight: maxImageHeight
        )?.cardSize
    }
    
    
    /// Resolves the on-disk file URL of a token identifier.
    func imageURL(for identifier: String, documentURL: URL?) -> URL? {
        
        if identifier.hasPrefix("/") {
            let direct = URL(filePath: identifier)
            if FileManager.default.fileExists(atPath: direct.path) {
                return direct
            }
        }
        
        if let documentURL {
            let localAsset = self.assetsFolder(for: documentURL).appending(path: identifier)
            if FileManager.default.fileExists(atPath: localAsset.path) {
                return localAsset
            }
            let sibling = documentURL.deletingLastPathComponent().appending(path: identifier)
            if FileManager.default.fileExists(atPath: sibling.path) {
                return sibling
            }
        }
        
        let globalAsset = self.assetsFolder(for: nil).appending(path: identifier)
        if FileManager.default.fileExists(atPath: globalAsset.path) {
            return globalAsset
        }
        
        return nil
    }
    
    
    // MARK: Private Helpers
    
    private func loadTransformMap(in folder: URL) -> [String: InlineImageTransform] {
        let url = folder.appending(path: "image-transforms.json")
        guard let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: InlineImageTransform].self, from: data)
        else { return [:] }
        return map
    }
    
    
    private static func writeTransformMap(_ map: [String: InlineImageTransform], in folder: URL) {
        let url = folder.appending(path: "image-transforms.json")
        if map.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: url, options: .atomic)
        }
    }
    
    
    private func cacheKey(for identifier: String, documentURL: URL?) -> String {
        
        if let documentURL {
            return "\(documentURL.deletingLastPathComponent().path)::\(identifier)"
        }
        return identifier
    }
    
    
    private func assetsFolder(for documentURL: URL?) -> URL {
        
        if let documentURL {
            return documentURL.deletingLastPathComponent().appending(path: ".cot-assets", directoryHint: .isDirectory)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appending(path: "Cot/InlineImages", directoryHint: .isDirectory)
    }
    
    
    private static func estimatedByteCost(for image: NSImage, logicalSize: NSSize) -> Int {
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
           rep.pixelsWide > 0, rep.pixelsHigh > 0
        {
            return max(1024, rep.pixelsWide * rep.pixelsHigh * 4)
        }
        let pxW = max(1, Int(logicalSize.width * 2))
        let pxH = max(1, Int(logicalSize.height * 2))
        return max(1024, pxW * pxH * 4)
    }
    
    
    private static func encodePNGPayload(from image: NSImage) -> (data: Data, renderedImage: NSImage, logicalSize: NSSize)? {
        
        var proposedRect = NSRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            // Preserve true pixel aspect ratio while applying Retina 2x point sizing when appropriate.
            let logical = self.logicalSize(pixelWidth: cgImage.width, pixelHeight: cgImage.height, hintedSize: image.size)
            if logical.width > 0, logical.height > 0 {
                bitmap.size = logical
            }
            if let png = bitmap.representation(using: .png, properties: [:]) {
                let cached = NSImage(size: bitmap.size)
                cached.addRepresentation(bitmap)
                return (png, cached, bitmap.size)
            }
        }
        
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let png = bitmap.representation(using: .png, properties: [:])
        {
            let logical = self.naturalImageSize(for: image)
            return (png, image, logical)
        }
        
        return nil
    }
}
