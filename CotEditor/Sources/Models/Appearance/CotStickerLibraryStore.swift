//
//  CotStickerLibraryStore.swift
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
import CryptoKit
import Foundation
import ImageIO
import Observation
import Vision

/// Manages the structured local Sticker/Meme library (`MediaLibrary/stickers/` + SQLite `user_stickers`),
/// on-device Vision OCR text extraction, AI vision semantic enrichment, and thumbnail caching.
@MainActor @Observable
final class CotStickerLibraryStore {
    
    static let shared = CotStickerLibraryStore()
    static let didChangeNotification = Notification.Name("CotEditorStickerLibraryDidChange")
    
    nonisolated static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif",
    ]
    
    private(set) var stickers: [StickerAsset] = []
    private(set) var revision: Int = 0
    private(set) var isImporting: Bool = false
    private(set) var isAnnotatingWithAI: Bool = false
    
    private let database: CotLocalDatabase
    let stickersDirectory: URL
    
    @ObservationIgnored private var shaIndex: [String: StickerAsset] = [:]
    @ObservationIgnored private var idIndex: [String: StickerAsset] = [:]
    @ObservationIgnored private let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        cache.countLimit = 300
        return cache
    }()
    @ObservationIgnored private var loadingThumbnailIDs: Set<String> = []
    
    
    init(database: CotLocalDatabase = .shared, stickersDirectory: URL? = nil) {
        self.database = database
        if let stickersDirectory {
            self.stickersDirectory = stickersDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            self.stickersDirectory = appSupport
                .appending(path: "CotEditor", directoryHint: .isDirectory)
                .appending(path: "MediaLibrary", directoryHint: .isDirectory)
                .appending(path: "stickers", directoryHint: .isDirectory)
        }
        self.reloadFromDatabase()
    }
    
    
    func reloadFromDatabase() {
        let items = self.database.fetchAllStickers()
        self.stickers = items
        self.rebuildIndexes()
        self.revision &+= 1
    }
    
    
    private func rebuildIndexes() {
        var byID: [String: StickerAsset] = [:]
        var bySHA: [String: StickerAsset] = [:]
        byID.reserveCapacity(self.stickers.count)
        bySHA.reserveCapacity(self.stickers.count)
        for item in self.stickers {
            byID[item.id] = item
            bySHA[item.sha256] = item
        }
        self.idIndex = byID
        self.shaIndex = bySHA
    }
    
    
    func sticker(id: String) -> StickerAsset? {
        self.idIndex[id]
    }
    
    
    func fileURL(for sticker: StickerAsset) -> URL {
        self.stickersDirectory.appending(path: sticker.fileName)
    }
    
    
    func imageData(for stickerID: String) -> (data: Data, mimeType: String)? {
        guard let sticker = self.idIndex[stickerID] else { return nil }
        let url = self.fileURL(for: sticker)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (data, Self.mimeType(for: sticker.format))
    }
    
    
    /// Returns a cached thumbnail immediately if available, or triggers background rasterization.
    func cachedOrLoadThumbnail(for sticker: StickerAsset, maxPixelSize: CGFloat = 220) -> NSImage? {
        let key = "\(sticker.id)@\(Int(maxPixelSize))" as NSString
        if let cached = self.thumbnailCache.object(forKey: key) {
            return cached
        }
        let loadKey = key as String
        guard !self.loadingThumbnailIDs.contains(loadKey) else { return nil }
        self.loadingThumbnailIDs.insert(loadKey)
        
        let fileURL = self.fileURL(for: sticker)
        let targetSide = Int(maxPixelSize)
        Task.detached(priority: .utility) {
            let thumb = Self.downsampleImage(at: fileURL, maxPixelSize: targetSide)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.loadingThumbnailIDs.remove(loadKey)
                if let thumb {
                    self.thumbnailCache.setObject(thumb, forKey: key, cost: targetSide * targetSide * 4)
                    self.revision &+= 1
                }
            }
        }
        return nil
    }
    
    
    func categoryCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for item in self.stickers {
            counts[item.category, default: 0] += 1
        }
        return counts
    }
    
    
    func search(
        query: String,
        mood: String? = nil,
        preferredCategories: [String] = [],
        onlyFavorites: Bool = false,
        categoryFilter: String? = nil,
        limit: Int = 24
    ) -> [StickerAsset] {
        StickerSearchEngine.search(
            self.stickers,
            query: query,
            mood: mood,
            preferredCategories: preferredCategories,
            onlyFavorites: onlyFavorites,
            categoryFilter: categoryFilter,
            limit: limit
        )
    }
    
    
    // MARK: - Mutations
    
    func toggleFavorite(id: String) {
        guard let idx = self.stickers.firstIndex(where: { $0.id == id }) else { return }
        let next = !self.stickers[idx].isFavorite
        self.stickers[idx].isFavorite = next
        self.database.setStickerFavorite(id: id, isFavorite: next)
        self.rebuildIndexes()
        self.revision &+= 1
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
    
    
    func recordUse(id: String) {
        let now = Date().timeIntervalSince1970
        if let idx = self.stickers.firstIndex(where: { $0.id == id }) {
            self.stickers[idx].useCount += 1
            self.stickers[idx].lastUsedAt = now
            self.rebuildIndexes()
            self.revision &+= 1
        }
        self.database.recordStickerUse(id: id, usedAt: now)
    }
    
    
    func updateSemantics(
        id: String,
        category: String,
        ocrText: String,
        meaning: String,
        moods: [String],
        tags: [String]
    ) {
        let normalizedCat = StickerCategory.normalize(category)
        self.database.updateStickerSemantics(
            id: id,
            category: normalizedCat,
            ocrText: ocrText.trimmingCharacters(in: .whitespacesAndNewlines),
            meaning: meaning.trimmingCharacters(in: .whitespacesAndNewlines),
            moods: moods,
            tags: tags
        )
        if let idx = self.stickers.firstIndex(where: { $0.id == id }) {
            self.stickers[idx].category = normalizedCat
            self.stickers[idx].ocrText = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
            self.stickers[idx].meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            self.stickers[idx].moods = moods
            self.stickers[idx].tags = tags
            self.rebuildIndexes()
            self.revision &+= 1
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
    
    
    func deleteSticker(id: String) {
        guard let target = self.idIndex[id] else { return }
        let fileURL = self.fileURL(for: target)
        try? FileManager.default.removeItem(at: fileURL)
        self.database.deleteSticker(id: id)
        self.stickers.removeAll { $0.id == id }
        self.rebuildIndexes()
        self.revision &+= 1
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
    
    
    // MARK: - Import & Storage
    
    func importFiles(_ urls: [URL], defaultCategory: String = "custom") async -> StickerImportResult {
        self.isImporting = true
        defer { self.isImporting = false }
        
        let discovered = Self.collectImportCandidates(from: urls, defaultCategory: defaultCategory)
        var result = StickerImportResult()
        var pendingAssets: [StickerAsset] = []
        let rootDir = self.stickersDirectory
        let existingSHAs = Set(self.shaIndex.keys)
        var batchSHAs: Set<String> = []
        
        let processed = await Task.detached(priority: .userInitiated) {
            var localAdded: [StickerAsset] = []
            var dupes = 0
            var failed = 0
            let fm = FileManager.default
            
            for entry in discovered {
                guard let data = try? Data(contentsOf: entry.url), !data.isEmpty else {
                    failed += 1
                    continue
                }
                let sha = Self.sha256Hex(data)
                if existingSHAs.contains(sha) || !batchSHAs.insert(sha).inserted {
                    dupes += 1
                    continue
                }
                guard let meta = Self.inspectImageMetadata(data: data, fallbackExt: entry.url.pathExtension) else {
                    failed += 1
                    continue
                }
                let cat = StickerCategory.normalize(entry.category)
                let stickerID = "stk_\(String(sha.prefix(16)))"
                let relPath = "\(cat)/\(stickerID).\(meta.fileExt)"
                let destURL = rootDir.appending(path: relPath)
                do {
                    try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: destURL, options: .atomic)
                } catch {
                    failed += 1
                    continue
                }
                
                let ocr = Self.recognizeTextSync(from: data)
                let inferred = StickerSearchEngine.inferMoodsAndTags(category: cat, ocrText: ocr, meaning: "")
                let asset = StickerAsset(
                    id: stickerID,
                    fileName: relPath,
                    category: cat,
                    format: meta.format,
                    width: meta.width,
                    height: meta.height,
                    bytes: data.count,
                    sha256: sha,
                    ocrText: ocr,
                    meaning: "",
                    moods: inferred.moods,
                    tags: inferred.tags,
                    sourceSite: entry.sourceSite,
                    sourceURL: entry.sourceURL,
                    isFavorite: false,
                    useCount: 0,
                    lastUsedAt: nil,
                    createdAt: Date().timeIntervalSince1970
                )
                localAdded.append(asset)
            }
            return (localAdded, dupes, failed)
        }.value
        
        pendingAssets = processed.0
        result.addedCount = pendingAssets.count
        result.skippedDuplicates = processed.1
        result.failedCount = processed.2
        result.firstAddedID = pendingAssets.first?.id
        
        if !pendingAssets.isEmpty {
            self.database.upsertStickers(pendingAssets)
            self.reloadFromDatabase()
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
        return result
    }
    
    
    func addImageData(
        _ data: Data,
        formatHint: String = "png",
        category: String = "custom",
        meaning: String = "",
        moods: [String] = [],
        tags: [String] = [],
        sourceSite: String = "local",
        sourceURL: String = ""
    ) async -> StickerAsset? {
        guard !data.isEmpty else { return nil }
        let sha = Self.sha256Hex(data)
        if let existing = self.shaIndex[sha] {
            return existing
        }
        let rootDir = self.stickersDirectory
        let normalizedCat = StickerCategory.normalize(category)
        let built: StickerAsset? = await Task.detached(priority: .userInitiated) {
            guard let meta = Self.inspectImageMetadata(data: data, fallbackExt: formatHint) else {
                return nil
            }
            let stickerID = "stk_\(String(sha.prefix(16)))"
            let relPath = "\(normalizedCat)/\(stickerID).\(meta.fileExt)"
            let destURL = rootDir.appending(path: relPath)
            do {
                try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destURL, options: .atomic)
            } catch {
                return nil
            }
            let ocr = Self.recognizeTextSync(from: data)
            let inferred = StickerSearchEngine.inferMoodsAndTags(category: normalizedCat, ocrText: ocr, meaning: meaning)
            let mergedMoods = Array(Set(moods + inferred.moods))
            let mergedTags = Array(Set(tags + inferred.tags))
            return StickerAsset(
                id: stickerID,
                fileName: relPath,
                category: normalizedCat,
                format: meta.format,
                width: meta.width,
                height: meta.height,
                bytes: data.count,
                sha256: sha,
                ocrText: ocr,
                meaning: meaning.trimmingCharacters(in: .whitespacesAndNewlines),
                moods: mergedMoods,
                tags: mergedTags,
                sourceSite: sourceSite,
                sourceURL: sourceURL,
                isFavorite: false,
                useCount: 0,
                lastUsedAt: nil,
                createdAt: Date().timeIntervalSince1970
            )
        }.value
        
        guard let built else { return nil }
        self.database.upsertSticker(built)
        self.reloadFromDatabase()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        return self.sticker(id: built.id) ?? built
    }
    
    
    /// Uses configured vision-capable AI to enrich `meaning`, `moods`, and `tags` for unannotated stickers.
    func annotateMissingWithVisionAI(limit: Int = 16) async -> Int {
        guard !self.isAnnotatingWithAI else { return 0 }
        let config = AIBotStore.shared.resolvedConfiguration(for: .ocrPolish)
        guard AIService.shared.isConfigured, config.isUsable else { return 0 }
        
        self.isAnnotatingWithAI = true
        defer { self.isAnnotatingWithAI = false }
        
        let targets = self.stickers
            .filter { $0.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(max(1, limit))
        var updatedCount = 0
        
        for item in targets {
            if Task.isCancelled { break }
            let url = self.fileURL(for: item)
            guard let jpegData = Self.compressedJPEGDataForVision(at: url) else { continue }
            let prompt = """
            请看这张表情包（分类：\(item.category)，OCR识别文字：\(item.ocrText.isEmpty ? "无" : item.ocrText)）。
            严格输出 JSON（不要多余文字）：
            {"meaning":"15字以内概括这张图表达的情绪或梗含义","moods":["开心/兴奋/平静/专注/摸鱼/无语/委屈 中选1-2个"],"tags":["3到5个中文检索词"]}
            """
            do {
                let raw = try await AIService.shared.chat(
                    [
                        .system("你是中文表情包语义标注器，只输出合法 JSON。"),
                        .user(prompt, images: [AIImage(data: jpegData, mimeType: "image/jpeg")]),
                    ],
                    configuration: config,
                    disablesThinking: true,
                    maxOutputTokens: 180,
                    timeoutInterval: 25,
                    analyticsFeature: "sticker_vision_tag"
                )
                if let parsed = Self.parseVisionAnnotationJSON(raw) {
                    let nextTags = Array(Set(item.tags + parsed.tags))
                    let nextMoods = parsed.moods.isEmpty ? item.moods : parsed.moods
                    self.updateSemantics(
                        id: item.id,
                        category: item.category,
                        ocrText: item.ocrText,
                        meaning: parsed.meaning,
                        moods: nextMoods,
                        tags: nextTags
                    )
                    updatedCount += 1
                }
            } catch {
                continue
            }
        }
        return updatedCount
    }
    
    
    // MARK: - Nonisolated File & Vision Helpers
    
    private nonisolated struct ImportCandidate: Sendable {
        let url: URL
        let category: String
        let sourceSite: String
        let sourceURL: String
    }
    
    private nonisolated struct IndexManifestEntry: Decodable {
        let file: String
        let category: String?
        let sourceSite: String?
        let sourceURL: String?
        
        enum CodingKeys: String, CodingKey {
            case file, category
            case sourceSite = "source_site"
            case sourceURL = "source_url"
        }
    }
    
    
    private nonisolated static func collectImportCandidates(from urls: [URL], defaultCategory: String) -> [ImportCandidate] {
        let fm = FileManager.default
        var results: [ImportCandidate] = []
        var seenPaths: Set<String> = []
        
        for rawURL in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: rawURL.path(percentEncoded: false), isDirectory: &isDir) else { continue }
            
            if !isDir.boolValue {
                let ext = rawURL.pathExtension.lowercased()
                if Self.supportedExtensions.contains(ext), seenPaths.insert(rawURL.path).inserted {
                    results.append(ImportCandidate(url: rawURL, category: defaultCategory, sourceSite: "local", sourceURL: ""))
                }
                continue
            }
            
            // Check for structured `index.json` manifest (e.g. /Users/cmy/Downloads/meme)
            let manifestURL = rawURL.appending(path: "index.json")
            if let data = try? Data(contentsOf: manifestURL),
               let entries = try? JSONDecoder().decode([IndexManifestEntry].self, from: data),
               !entries.isEmpty
            {
                for entry in entries {
                    let itemURL = rawURL.appending(path: entry.file)
                    let ext = itemURL.pathExtension.lowercased()
                    if fm.fileExists(atPath: itemURL.path(percentEncoded: false)),
                       Self.supportedExtensions.contains(ext),
                       seenPaths.insert(itemURL.path).inserted
                    {
                        results.append(ImportCandidate(
                            url: itemURL,
                            category: entry.category ?? itemURL.deletingLastPathComponent().lastPathComponent,
                            sourceSite: entry.sourceSite ?? "local",
                            sourceURL: entry.sourceURL ?? ""
                        ))
                    }
                }
            }
            
            if let enumerator = fm.enumerator(
                at: rawURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                while let fileURL = enumerator.nextObject() as? URL {
                    let ext = fileURL.pathExtension.lowercased()
                    guard Self.supportedExtensions.contains(ext),
                          seenPaths.insert(fileURL.path).inserted
                    else { continue }
                    let parentName = fileURL.deletingLastPathComponent().lastPathComponent
                    let cat = parentName == rawURL.lastPathComponent ? defaultCategory : parentName
                    results.append(ImportCandidate(url: fileURL, category: cat, sourceSite: "local", sourceURL: ""))
                }
            }
        }
        return results
    }
    
    
    private nonisolated static func inspectImageMetadata(
        data: Data,
        fallbackExt: String
    ) -> (format: String, fileExt: String, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard width > 0, height > 0 else { return nil }
        
        let uti = (CGImageSourceGetType(source) as String?)?.lowercased() ?? ""
        let lowerExt = fallbackExt.lowercased()
        let format: String
        let fileExt: String
        if uti.contains("gif") || lowerExt == "gif" {
            format = "gif"; fileExt = "gif"
        } else if uti.contains("png") || lowerExt == "png" {
            format = "png"; fileExt = "png"
        } else if uti.contains("webp") || lowerExt == "webp" {
            format = "webp"; fileExt = "webp"
        } else {
            format = "jpeg"; fileExt = "jpg"
        }
        return (format, fileExt, width, height)
    }
    
    
    nonisolated static func recognizeTextSync(from data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    private nonisolated static func downsampleImage(at url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
    
    
    private nonisolated static func compressedJPEGDataForVision(at url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 384,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.78])
    }
    
    
    private nonisolated static func parseVisionAnnotationJSON(_ raw: String) -> (meaning: String, moods: [String], tags: [String])? {
        struct Payload: Decodable {
            let meaning: String?
            let moods: [String]?
            let tags: [String]?
        }
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}")
        else { return nil }
        let jsonStr = String(raw[start...end])
        guard let data = jsonStr.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        let meaning = decoded.meaning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let moods = (decoded.moods ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let tags = (decoded.tags ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !meaning.isEmpty || !tags.isEmpty else { return nil }
        return (meaning, moods, tags)
    }
    
    
    nonisolated static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    
    nonisolated static func mimeType(for format: String) -> String {
        switch format.lowercased() {
            case "gif": "image/gif"
            case "png": "image/png"
            case "webp": "image/webp"
            default: "image/jpeg"
        }
    }
}
