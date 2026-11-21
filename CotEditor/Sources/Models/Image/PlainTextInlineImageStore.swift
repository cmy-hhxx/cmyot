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

/// Stepless user customization transform (zoom, free X/Y offset, rotation) for an inline image.
nonisolated struct InlineImageTransform: Codable, Equatable, Sendable {
    
    var scale: CGFloat = 1.0          // 0.15 ... 4.0 (stepless)
    var offsetX: CGFloat = 0.0        // Horizontal offset inside editor canvas
    var offsetY: CGFloat = 0.0        // Extra top padding (0 ... 240)
    var rotationDegrees: CGFloat = 0  // Stepless angle (-180 ... +180)
    
    var isIdentity: Bool {
        abs(self.scale - 1.0) < 0.001 &&
        abs(self.offsetX) < 0.5 &&
        abs(self.offsetY) < 0.5 &&
        abs(self.rotationDegrees) < 0.1
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


/// Manages images embedded inside a Plain Text document (`SyntaxName.none`).
///
/// The text file stays 100% pure plain text by storing a compact token `⟦🖼 <filename>⟧`
/// while the image file itself lives in a hidden `.cot-assets/` folder beside the document
/// (or in `~/Library/Application Support/Cot/InlineImages/` for untitled documents).
/// In the editor, `EditorTextView` and `LayoutManager` render a sleek inline card right under
/// the line containing the token, supporting stepless zoom, position offset, and rotation.
nonisolated final class PlainTextInlineImageStore: @unchecked Sendable {
    
    static let shared = PlainTextInlineImageStore()
    
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
    
    private let lock = NSLock()
    private var imageCache: [String: NSImage] = [:]
    private var imageSizeCache: [String: NSSize] = [:]
    private var transformsByFolder: [String: [String: InlineImageTransform]] = [:]
    
    
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
        
        guard let pngData = Self.encodePNG(from: image) else { return nil }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let shortID = String(UUID().uuidString.prefix(4)).lowercased()
        let filename = "img-\(stamp)-\(shortID).png"
        
        let folder = self.assetsFolder(for: documentURL)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        
        let targetURL = folder.appending(path: filename)
        do {
            try pngData.write(to: targetURL, options: .atomic)
        } catch {
            return nil
        }
        
        self.lock.withLock {
            if let normalized = NSImage(data: pngData) {
                let logicalSize = Self.naturalImageSize(for: normalized)
                self.imageCache[targetURL.path] = normalized
                self.imageCache[filename] = normalized
                self.imageSizeCache[targetURL.path] = logicalSize
                self.imageSizeCache[filename] = logicalSize
            } else {
                let logicalSize = Self.naturalImageSize(for: image)
                self.imageCache[targetURL.path] = image
                self.imageCache[filename] = image
                self.imageSizeCache[targetURL.path] = logicalSize
                self.imageSizeCache[filename] = logicalSize
            }
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
            
            let globalTransform = self.transform(for: token.identifier, documentURL: nil)
            if !globalTransform.isIdentity {
                self.setTransform(globalTransform, for: token.identifier, documentURL: documentURL)
            }
        }
    }
    
    
    /// Finds all inline image tokens inside the given `NSString` range.
    func findTokens(in string: NSString, range: NSRange) -> [(range: NSRange, identifier: String)] {
        
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: string.length))
        guard safeRange.length > 0 else { return [] }
        
        return Self.tokenRegex.matches(in: string as String, range: safeRange).compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            let identifier = string.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            return (match.range, identifier)
        }
    }
    
    
    /// Resolves and caches the `NSImage` for a token identifier.
    func image(for identifier: String, documentURL: URL?) -> NSImage? {
        
        let cacheKey = self.cacheKey(for: identifier, documentURL: documentURL)
        if let cached = self.lock.withLock({ self.imageCache[cacheKey] ?? self.imageCache[identifier] }) {
            return cached
        }
        
        if let url = self.imageURL(for: identifier, documentURL: documentURL),
           let loaded = NSImage(contentsOf: url)
        {
            let logicalSize = Self.naturalImageSize(for: loaded)
            self.lock.withLock {
                self.imageCache[cacheKey] = loaded
                self.imageCache[identifier] = loaded
                self.imageSizeCache[cacheKey] = logicalSize
                self.imageSizeCache[identifier] = logicalSize
            }
            return loaded
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
    
    
    /// Returns an aspect-fit rectangle centered inside `bounds`, preserving exact `imageSize` proportions.
    static func aspectFitRect(imageSize: NSSize, in bounds: NSRect) -> NSRect {
        
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = bounds.minX + (bounds.width - width) / 2
        let y = bounds.minY + (bounds.height - height) / 2
        return NSRect(x: x, y: y, width: width, height: height)
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
    func setTransform(_ transform: InlineImageTransform, for identifier: String, documentURL: URL?) {
        
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
        self.saveTransformMap(updatedMap, in: folder)
    }
    
    
    func resetTransform(for identifier: String, documentURL: URL?) {
        self.setTransform(.identity, for: identifier, documentURL: documentURL)
    }
    
    
    /// Computes complete display geometry accounting for stepless scale, rotation bounding box, and spacing.
    func displayGeometry(
        for identifier: String,
        documentURL: URL?,
        containerWidth: CGFloat,
        maxImageWidth: CGFloat = 460,
        maxImageHeight: CGFloat = 260
    ) -> InlineImageDisplayGeometry? {
        
        let cacheKey = self.cacheKey(for: identifier, documentURL: documentURL)
        let naturalSize: NSSize?
        if let cached = self.lock.withLock({ self.imageSizeCache[cacheKey] ?? self.imageSizeCache[identifier] }) {
            naturalSize = cached
        } else if let img = self.image(for: identifier, documentURL: documentURL) {
            naturalSize = Self.naturalImageSize(for: img)
        } else {
            naturalSize = nil
        }
        
        guard let imgSize = naturalSize, imgSize.width > 0, imgSize.height > 0 else { return nil }
        
        let baseScale = min(maxImageWidth / imgSize.width, maxImageHeight / imgSize.height, 1.0)
        let baseDrawW = max(1, round(imgSize.width * baseScale))
        let baseDrawH = max(1, round(imgSize.height * baseScale))
        let transform = self.transform(for: identifier, documentURL: documentURL)
        
        if transform.isIdentity {
            let drawSize = NSSize(width: baseDrawW, height: baseDrawH)
            return InlineImageDisplayGeometry(
                drawSize: drawSize,
                rotatedBoxSize: drawSize,
                cardSize: NSSize(width: baseDrawW + 8, height: baseDrawH + 8),
                transform: .identity
            )
        }
        
        // When user explicitly scales (> 1.0), break past the 460pt thumbnail cap up to full editor canvas width.
        let canvasMaxW = max(maxImageWidth, max(160, containerWidth - 24))
        let rawScaledW = baseDrawW * transform.scale
        let clampedW = max(36, min(canvasMaxW, round(rawScaledW)))
        let aspect = imgSize.height / imgSize.width
        let clampedH = max(24, round(clampedW * aspect))
        
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
    
    
    private func saveTransformMap(_ map: [String: InlineImageTransform], in folder: URL) {
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
            return "\(documentURL.path)::\(identifier)"
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
    
    
    private static func encodePNG(from image: NSImage) -> Data? {
        
        var proposedRect = NSRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            // Preserve true pixel aspect ratio while applying Retina 2x point sizing when appropriate.
            let logical = self.logicalSize(pixelWidth: cgImage.width, pixelHeight: cgImage.height, hintedSize: image.size)
            if logical.width > 0, logical.height > 0 {
                bitmap.size = logical
            }
            if let png = bitmap.representation(using: .png, properties: [:]) {
                return png
            }
        }
        
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let png = bitmap.representation(using: .png, properties: [:])
        {
            return png
        }
        
        return nil
    }
}
