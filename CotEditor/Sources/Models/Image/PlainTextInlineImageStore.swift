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

/// Manages images embedded inside a Plain Text document (`SyntaxName.none`).
///
/// The text file stays 100% pure plain text by storing a compact token `⟦🖼 <filename>⟧`
/// while the image file itself lives in a hidden `.cot-assets/` folder beside the document
/// (or in `~/Library/Application Support/Cot/InlineImages/` for untitled documents).
/// In the editor, `EditorTextView` and `LayoutManager` render a sleek inline thumbnail card
/// right under the line containing the token.
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
                self.imageCache[targetURL.path] = normalized
                self.imageCache[filename] = normalized
                self.imageSizeCache[targetURL.path] = normalized.size
                self.imageSizeCache[filename] = normalized.size
            } else {
                self.imageCache[targetURL.path] = image
                self.imageCache[filename] = image
                self.imageSizeCache[targetURL.path] = image.size
                self.imageSizeCache[filename] = image.size
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
            guard
                FileManager.default.fileExists(atPath: sourceURL.path),
                !FileManager.default.fileExists(atPath: destURL.path)
            else { continue }
            
            try? FileManager.default.createDirectory(at: docFolder, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: sourceURL, to: destURL)
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
            self.lock.withLock {
                self.imageCache[cacheKey] = loaded
                self.imageCache[identifier] = loaded
                self.imageSizeCache[cacheKey] = loaded.size
                self.imageSizeCache[identifier] = loaded.size
            }
            return loaded
        }
        
        return nil
    }
    
    
    /// Returns the scaled card size (including padding) for an inline image token, or `nil` if unresolved.
    func cardSize(
        for identifier: String,
        documentURL: URL?,
        maxImageWidth: CGFloat = 440,
        maxImageHeight: CGFloat = 210
    ) -> NSSize? {
        
        let cacheKey = self.cacheKey(for: identifier, documentURL: documentURL)
        let naturalSize: NSSize?
        if let cached = self.lock.withLock({ self.imageSizeCache[cacheKey] ?? self.imageSizeCache[identifier] }) {
            naturalSize = cached
        } else {
            naturalSize = self.image(for: identifier, documentURL: documentURL)?.size
        }
        
        guard let imgSize = naturalSize, imgSize.width > 0, imgSize.height > 0 else { return nil }
        
        let scale = min(maxImageWidth / imgSize.width, maxImageHeight / imgSize.height, 1.0)
        let drawWidth = max(64, round(imgSize.width * scale))
        let drawHeight = max(44, round(imgSize.height * scale))
        return NSSize(width: drawWidth + 12, height: drawHeight + 12)
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
            // Preserve Retina point size when pixel size is 2x so inline thumbnails don't blow up unnecessarily
            if image.size.width > 0, image.size.height > 0 {
                bitmap.size = image.size
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
