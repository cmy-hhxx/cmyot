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

/// Manages images embedded inside a Plain Text document (`SyntaxName.none`).
///
/// The text file stays 100% pure plain text by storing a compact token `⟦🖼 <filename>⟧`
/// while the image file itself lives in a hidden `.cot-assets/` folder beside the document
/// (or in `~/Library/Application Support/Cot/InlineImages/` for untitled documents).
/// In the editor, `EditorTextView` and `LayoutManager` render a sleek inline thumbnail card
/// right under the line containing the token.
@MainActor final class PlainTextInlineImageStore {
    
    static let shared = PlainTextInlineImageStore()
    
    private static let tokenRegex = try! NSRegularExpression(pattern: "⟦🖼\\s*([^⟧]+?)⟧")
    
    private var imageCache: [String: NSImage] = [:]
    
    
    /// Stores a pasted or dropped `NSImage` for a document and returns the plain-text token to insert.
    ///
    /// - Parameters:
    ///   - image: The image to store.
    ///   - documentURL: The file URL of the document, if saved.
    /// - Returns: The token string (e.g. `⟦🖼 img-20261117-1620.png⟧`) and its saved file URL.
    func store(image: NSImage, for documentURL: URL?) -> (token: String, fileURL: URL)? {
        
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        
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
        
        self.imageCache[targetURL.path] = image
        self.imageCache[filename] = image
        
        return ("⟦🖼 \(filename)⟧", targetURL)
    }
    
    
    /// Copies an existing dropped image file into the assets store and returns the token.
    func storeImageFile(at sourceURL: URL, for documentURL: URL?) -> (token: String, fileURL: URL)? {
        
        guard let image = NSImage(contentsOf: sourceURL) else { return nil }
        return self.store(image: image, for: documentURL)
    }
    
    
    /// Finds all inline image tokens inside the given `NSString` range.
    ///
    /// - Parameters:
    ///   - string: The full document string.
    ///   - range: The character range to scan.
    /// - Returns: Matched token ranges and their image identifiers.
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
        
        if let cached = self.imageCache[identifier] {
            return cached
        }
        
        if let url = self.imageURL(for: identifier, documentURL: documentURL),
           let loaded = NSImage(contentsOf: url)
        {
            self.imageCache[identifier] = loaded
            return loaded
        }
        
        return nil
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
    
    private func assetsFolder(for documentURL: URL?) -> URL {
        
        if let documentURL {
            return documentURL.deletingLastPathComponent().appending(path: ".cot-assets", directoryHint: .isDirectory)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appending(path: "Cot/InlineImages", directoryHint: .isDirectory)
    }
}
