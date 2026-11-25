//
//  UserMediaLibraryStore.swift
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
import ImageIO
import Observation
import SwiftUI

nonisolated enum UserMediaKind: String, Codable, CaseIterable, Identifiable, Sendable {
    
    case avatar
    case background
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
            case .avatar: AppLanguage.text("头像库", en: "Avatars")
            case .background: AppLanguage.text("背景库", en: "Backgrounds")
        }
    }
    
    var symbolName: String {
        switch self {
            case .avatar: "person.crop.circle.fill"
            case .background: "photo.fill.on.rectangle.fill"
        }
    }
}


nonisolated enum MediaAspectPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    
    case original
    case square
    case portrait3x4
    case landscape4x3
    case landscape16x10
    case landscape16x9
    case ultrawide21x9
    
    var id: String { self.rawValue }
    
    var label: String {
        switch self {
            case .original: AppLanguage.text("原始", en: "Original")
            case .square: "1:1"
            case .portrait3x4: "3:4"
            case .landscape4x3: "4:3"
            case .landscape16x10: "16:10"
            case .landscape16x9: "16:9"
            case .ultrawide21x9: "21:9"
        }
    }
    
    var aspectRatio: CGFloat? {
        switch self {
            case .original: nil
            case .square: 1.0
            case .portrait3x4: 3.0 / 4.0
            case .landscape4x3: 4.0 / 3.0
            case .landscape16x10: 16.0 / 10.0
            case .landscape16x9: 16.0 / 9.0
            case .ultrawide21x9: 21.0 / 9.0
        }
    }
    
    static func presets(for kind: UserMediaKind) -> [MediaAspectPreset] {
        switch kind {
            case .avatar:
                [.square, .portrait3x4, .original]
            case .background:
                [.original, .landscape16x10, .landscape16x9, .ultrawide21x9, .landscape4x3, .square]
        }
    }
}


nonisolated struct UserMediaEditSpec: Codable, Equatable, Sendable {
    
    var scale: Double = 1.0           // 1.0 ... 4.0
    var panX: Double = 0.0            // -1.0 ... 1.0
    var panY: Double = 0.0            // -1.0 ... 1.0
    var aspectPreset: MediaAspectPreset = .original
    var quarterTurns: Int = 0         // 0, 1, 2, 3 (90° clockwise)
    var flipHorizontal: Bool = false
    
    static let identity = UserMediaEditSpec()
    
    var isIdentity: Bool {
        abs(self.scale - 1.0) < 0.005
            && abs(self.panX) < 0.005
            && abs(self.panY) < 0.005
            && self.aspectPreset == .original
            && ((self.quarterTurns % 4) == 0)
            && !self.flipHorizontal
    }
    
    func clamped() -> UserMediaEditSpec {
        UserMediaEditSpec(
            scale: max(1.0, min(4.0, self.scale)),
            panX: max(-1.0, min(1.0, self.panX)),
            panY: max(-1.0, min(1.0, self.panY)),
            aspectPreset: self.aspectPreset,
            quarterTurns: ((self.quarterTurns % 4) + 4) % 4,
            flipHorizontal: self.flipHorizontal
        )
    }
}


nonisolated struct UserMediaAsset: Identifiable, Codable, Equatable, Sendable {
    
    let id: String
    let kind: UserMediaKind
    var title: String
    let filename: String
    let contentSHA256: String
    var pixelWidth: Int
    var pixelHeight: Int
    let createdAt: Date
    var editSpec: UserMediaEditSpec? = nil
    var originalFilename: String? = nil
    
    enum CodingKeys: String, CodingKey {
        case id, kind, title, filename, contentSHA256, pixelWidth, pixelHeight, createdAt, editSpec, originalFilename
    }
    
    init(
        id: String,
        kind: UserMediaKind,
        title: String,
        filename: String,
        contentSHA256: String,
        pixelWidth: Int,
        pixelHeight: Int,
        createdAt: Date,
        editSpec: UserMediaEditSpec? = nil,
        originalFilename: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.filename = filename
        self.contentSHA256 = contentSHA256
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.createdAt = createdAt
        self.editSpec = editSpec
        self.originalFilename = originalFilename
    }
    
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.kind = try c.decode(UserMediaKind.self, forKey: .kind)
        self.title = try c.decode(String.self, forKey: .title)
        self.filename = try c.decode(String.self, forKey: .filename)
        self.contentSHA256 = try c.decode(String.self, forKey: .contentSHA256)
        self.pixelWidth = try c.decode(Int.self, forKey: .pixelWidth)
        self.pixelHeight = try c.decode(Int.self, forKey: .pixelHeight)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.editSpec = try c.decodeIfPresent(UserMediaEditSpec.self, forKey: .editSpec)
        self.originalFilename = try c.decodeIfPresent(String.self, forKey: .originalFilename)
    }
}


nonisolated enum BoardBackgroundSlot: String, Codable, CaseIterable, Identifiable, Sendable {
    
    case market
    case podcast
    case news
    case butler
    
    var id: String { self.rawValue }
    
    init(paneBoardKind: PaneBoardKind) {
        switch paneBoardKind {
            case .market: self = .market
            case .podcast: self = .podcast
            case .news: self = .news
            case .butler: self = .butler
        }
    }
    
    var title: String {
        switch self {
            case .market: AppLanguage.text("股票看盘看板", en: "Markets Board")
            case .podcast: AppLanguage.text("播客看板", en: "Podcasts Board")
            case .news: AppLanguage.text("资讯看板", en: "News Board")
            case .butler: AppLanguage.text("总管看板", en: "Butler Board")
        }
    }
    
    var shortTitle: String {
        switch self {
            case .market: AppLanguage.text("看盘", en: "Markets")
            case .podcast: AppLanguage.text("播客", en: "Podcasts")
            case .news: AppLanguage.text("资讯", en: "News")
            case .butler: AppLanguage.text("总管", en: "Butler")
        }
    }
    
    var symbolName: String {
        switch self {
            case .market: "chart.xyaxis.line"
            case .podcast: "waveform"
            case .news: "newspaper"
            case .butler: "person.crop.rectangle.stack"
        }
    }
}


nonisolated struct BoardBackgroundAssignment: Codable, Equatable, Sendable {
    
    var assetID: String
    var opacity: Double = 0.24
    var blurRadius: Double = 10.0
    
    func clamped() -> BoardBackgroundAssignment {
        BoardBackgroundAssignment(
            assetID: self.assetID,
            opacity: max(0.06, min(0.55, self.opacity)),
            blurRadius: max(0.0, min(28.0, self.blurRadius))
        )
    }
}


nonisolated struct MediaLibraryImportResult: Equatable, Sendable {
    
    var avatarsAdded: Int = 0
    var backgroundsAdded: Int = 0
    var skippedDuplicates: Int = 0
    var failedCount: Int = 0
    var firstAddedAvatarID: String? = nil
    var firstAddedBackgroundID: String? = nil
    
    var totalAdded: Int {
        self.avatarsAdded + self.backgroundsAdded
    }
    
    var summaryText: String {
        var parts: [String] = []
        if self.avatarsAdded > 0 {
            parts.append(AppLanguage.text("新增 \(self.avatarsAdded) 张头像", en: "Added \(self.avatarsAdded) avatars"))
        }
        if self.backgroundsAdded > 0 {
            parts.append(AppLanguage.text("新增 \(self.backgroundsAdded) 张背景", en: "Added \(self.backgroundsAdded) backgrounds"))
        }
        if self.skippedDuplicates > 0 {
            parts.append(AppLanguage.text("跳过 \(self.skippedDuplicates) 张重复", en: "\(self.skippedDuplicates) duplicates skipped"))
        }
        if self.failedCount > 0 {
            parts.append(AppLanguage.text("\(self.failedCount) 个无法解析", en: "\(self.failedCount) failed"))
        }
        if parts.isEmpty {
            return AppLanguage.text("未发现可导入的图片", en: "No supported images found")
        }
        return parts.joined(separator: " · ")
    }
}


/// Manages the user's persistent Avatar Library and Background Library,
/// supporting multi-file & smart-folder import (`avatars/`, `bgs/`), deduplication,
/// thumbnail caching, and one-click assignment across Bots, Wallpaper, Hero Cover, and Boards.
@MainActor @Observable
final class UserMediaLibraryStore {
    
    static let shared = UserMediaLibraryStore()
    static let didChangeNotification = Notification.Name("CotEditorUserMediaLibraryDidChange")
    
    nonisolated static let supportedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "heic", "heif", "tiff", "tif", "bmp", "gif",
    ]
    
    private nonisolated static let avatarFolderNames: Set<String> = [
        "avatars", "avatar", "headshots", "portraits", "头像", "头像库",
    ]
    private nonisolated static let backgroundFolderNames: Set<String> = [
        "bgs", "bg", "backgrounds", "background", "wallpapers", "wallpaper", "covers", "cover", "背景", "背景库", "壁纸",
    ]
    
    private(set) var avatars: [UserMediaAsset] = []
    private(set) var backgrounds: [UserMediaAsset] = []
    private(set) var boardAssignments: [String: BoardBackgroundAssignment] = [:]
    private(set) var revision: Int = 0
    
    private let database: CotLocalDatabase
    private let storageDirectory: URL
    
    @ObservationIgnored private let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 120
        return cache
    }()
    
    @ObservationIgnored private let fullImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        cache.countLimit = 16
        return cache
    }()
    
    
    init(database: CotLocalDatabase = .shared, storageDirectory: URL? = nil) {
        self.database = database
        if let storageDirectory {
            self.storageDirectory = storageDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            self.storageDirectory = appSupport
                .appending(path: "CotEditor", directoryHint: .isDirectory)
                .appending(path: "MediaLibrary", directoryHint: .isDirectory)
        }
        self.reloadFromDatabase()
    }
    
    
    func reloadFromDatabase() {
        let decoder = JSONDecoder()
        
        let rawAvatars = self.database.string(forKey: CotLocalDatabase.ConfigKey.userAvatarLibraryJSON)
        if let data = rawAvatars.data(using: .utf8),
           let decoded = try? decoder.decode([UserMediaAsset].self, from: data)
        {
            self.avatars = decoded
        } else {
            self.avatars = []
        }
        
        let rawBackgrounds = self.database.string(forKey: CotLocalDatabase.ConfigKey.userBackgroundLibraryJSON)
        if let data = rawBackgrounds.data(using: .utf8),
           let decoded = try? decoder.decode([UserMediaAsset].self, from: data)
        {
            self.backgrounds = decoded
        } else {
            self.backgrounds = []
        }
        
        let rawAssignments = self.database.string(forKey: CotLocalDatabase.ConfigKey.boardBackgroundAssignmentsJSON)
        if let data = rawAssignments.data(using: .utf8),
           let decoded = try? decoder.decode([String: BoardBackgroundAssignment].self, from: data)
        {
            self.boardAssignments = decoded.mapValues { $0.clamped() }
        } else {
            self.boardAssignments = [:]
        }
        
        self.thumbnailCache.removeAllObjects()
        self.fullImageCache.removeAllObjects()
        self.revision &+= 1
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
    
    
    // MARK: - Queries & Storage Paths
    
    func assets(for kind: UserMediaKind) -> [UserMediaAsset] {
        switch kind {
            case .avatar: self.avatars
            case .background: self.backgrounds
        }
    }
    
    func asset(id: String, kind: UserMediaKind) -> UserMediaAsset? {
        self.assets(for: kind).first { $0.id == id }
    }
    
    func directory(for kind: UserMediaKind) -> URL {
        let folder = (kind == .avatar) ? "avatars" : "backgrounds"
        return self.storageDirectory.appending(path: folder, directoryHint: .isDirectory)
    }
    
    func fileURL(for asset: UserMediaAsset) -> URL {
        self.directory(for: asset.kind).appending(path: asset.filename)
    }
    
    func originalsDirectory(for kind: UserMediaKind) -> URL {
        self.directory(for: kind).appending(path: "originals", directoryHint: .isDirectory)
    }
    
    func originalFileURL(for asset: UserMediaAsset) -> URL {
        if let orig = asset.originalFilename {
            let candidate = self.originalsDirectory(for: asset.kind).appending(path: orig)
            if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }
        return self.fileURL(for: asset)
    }
    
    func originalImage(for asset: UserMediaAsset) -> NSImage? {
        let url = self.originalFileURL(for: asset)
        let maxDim: CGFloat = (asset.kind == .avatar) ? 1024 : 2400
        if let cg = Self.normalizedCGImage(fromURL: url, maxDimension: maxDim) {
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        return NSImage(contentsOf: url)
    }
    
    func thumbnailImage(for asset: UserMediaAsset, maxPixelSize: CGFloat = 320) -> NSImage? {
        let key = "\(asset.id)@\(Int(maxPixelSize))" as NSString
        if let cached = self.thumbnailCache.object(forKey: key) {
            return cached
        }
        let url = self.fileURL(for: asset)
        guard let cg = Self.normalizedCGImage(fromURL: url, maxDimension: maxPixelSize) else {
            return nil
        }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        self.thumbnailCache.setObject(image, forKey: key, cost: Self.estimatedCost(of: image))
        return image
    }
    
    func fullImage(for asset: UserMediaAsset) -> NSImage? {
        let key = asset.id as NSString
        if let cached = self.fullImageCache.object(forKey: key) {
            return cached
        }
        let url = self.fileURL(for: asset)
        let maxDim: CGFloat = (asset.kind == .avatar) ? 512 : 2400
        if let cg = Self.normalizedCGImage(fromURL: url, maxDimension: maxDim) {
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            self.fullImageCache.setObject(image, forKey: key, cost: Self.estimatedCost(of: image))
            return image
        }
        if let fallback = NSImage(contentsOf: url) {
            self.fullImageCache.setObject(fallback, forKey: key, cost: Self.estimatedCost(of: fallback))
            return fallback
        }
        return nil
    }
    
    
    // MARK: - Import & CRUD
    
    @discardableResult
    func addImage(from url: URL, kind: UserMediaKind, customTitle: String? = nil) -> (asset: UserMediaAsset?, isDuplicate: Bool) {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let sourceData = try? Data(contentsOf: url), !sourceData.isEmpty else {
            return (nil, false)
        }
        let hash = Self.sha256Hex(sourceData)
        if let existing = self.assets(for: kind).first(where: { $0.contentSHA256 == hash }) {
            return (existing, true)
        }
        
        let maxDim: CGFloat = (kind == .avatar) ? 512 : 2400
        guard let cgImage = Self.normalizedCGImage(fromData: sourceData, maxDimension: maxDim),
              let encoded = Self.encodeNormalizedImage(cgImage, kind: kind)
        else {
            return (nil, false)
        }
        
        let rawTitle = (customTitle ?? url.deletingPathExtension().lastPathComponent)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackPrefix = (kind == .avatar) ? "头像" : "背景"
        let title = rawTitle.isEmpty ? "\(fallbackPrefix) \(self.assets(for: kind).count + 1)" : rawTitle
        
        guard let stored = self.storeEncodedAsset(
            data: encoded.data,
            fileExtension: encoded.fileExtension,
            width: encoded.width,
            height: encoded.height,
            hash: hash,
            title: title,
            kind: kind
        ) else {
            return (nil, false)
        }
        return (stored, false)
    }
    
    
    @discardableResult
    func addImage(_ image: NSImage, title: String, kind: UserMediaKind) -> (asset: UserMediaAsset?, isDuplicate: Bool) {
        let maxDim: CGFloat = (kind == .avatar) ? 512 : 2400
        guard let cg = Self.underlyingCGImage(from: image),
              let encoded = Self.encodeNormalizedImage(cg, kind: kind, maxDimension: maxDim)
        else {
            return (nil, false)
        }
        let hash = Self.sha256Hex(encoded.data)
        if let existing = self.assets(for: kind).first(where: { $0.contentSHA256 == hash }) {
            return (existing, true)
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackPrefix = (kind == .avatar) ? "头像" : "背景"
        let resolvedTitle = trimmedTitle.isEmpty ? "\(fallbackPrefix) \(self.assets(for: kind).count + 1)" : trimmedTitle
        guard let stored = self.storeEncodedAsset(
            data: encoded.data,
            fileExtension: encoded.fileExtension,
            width: encoded.width,
            height: encoded.height,
            hash: hash,
            title: resolvedTitle,
            kind: kind
        ) else {
            return (nil, false)
        }
        return (stored, false)
    }
    
    
    /// Imports image files and/or directories.
    /// Directories with `avatars/` or `bgs/` / `backgrounds/` folder names automatically route to their respective libraries.
    @discardableResult
    func importURLs(_ urls: [URL], preferredKind: UserMediaKind) -> MediaLibraryImportResult {
        var result = MediaLibraryImportResult()
        var pendingItems: [(url: URL, kind: UserMediaKind)] = []
        
        for rawURL in urls {
            let hasScope = rawURL.startAccessingSecurityScopedResource()
            defer {
                if hasScope { rawURL.stopAccessingSecurityScopedResource() }
            }
            
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: rawURL.path, isDirectory: &isDirectory) else {
                continue
            }
            
            if isDirectory.boolValue {
                let collected = Self.collectImagesFromDirectory(rawURL, fallbackKind: preferredKind)
                pendingItems.append(contentsOf: collected)
            } else if Self.isSupportedImageURL(rawURL) {
                pendingItems.append((rawURL, preferredKind))
            }
        }
        
        for item in pendingItems {
            let outcome = self.addImage(from: item.url, kind: item.kind)
            if outcome.isDuplicate {
                result.skippedDuplicates += 1
            } else if let asset = outcome.asset {
                switch item.kind {
                    case .avatar:
                        result.avatarsAdded += 1
                        if result.firstAddedAvatarID == nil {
                            result.firstAddedAvatarID = asset.id
                        }
                    case .background:
                        result.backgroundsAdded += 1
                        if result.firstAddedBackgroundID == nil {
                            result.firstAddedBackgroundID = asset.id
                        }
                }
            } else {
                result.failedCount += 1
            }
        }
        
        return result
    }
    
    
    func deleteAsset(id: String, kind: UserMediaKind) {
        let url: URL?
        let originalURL: URL?
        switch kind {
            case .avatar:
                guard let idx = self.avatars.firstIndex(where: { $0.id == id }) else { return }
                let removed = self.avatars.remove(at: idx)
                url = self.fileURL(for: removed)
                originalURL = removed.originalFilename.map { self.originalsDirectory(for: .avatar).appending(path: $0) }
                self.persistCatalog(for: .avatar)
            case .background:
                guard let idx = self.backgrounds.firstIndex(where: { $0.id == id }) else { return }
                let removed = self.backgrounds.remove(at: idx)
                url = self.fileURL(for: removed)
                originalURL = removed.originalFilename.map { self.originalsDirectory(for: .background).appending(path: $0) }
                self.persistCatalog(for: .background)
                
                var assignmentsChanged = false
                for (slotKey, assignment) in self.boardAssignments where assignment.assetID == id {
                    self.boardAssignments.removeValue(forKey: slotKey)
                    assignmentsChanged = true
                }
                if assignmentsChanged {
                    self.persistBoardAssignments()
                }
                
                if self.database === CotLocalDatabase.shared {
                    let libWallpaperID = WallpaperManager.mediaLibraryWallpaperID(for: id)
                    if WallpaperManager.shared.customRecords.contains(where: { $0.id == libWallpaperID }) {
                        WallpaperManager.shared.deleteCustomWallpaper(id: libWallpaperID)
                    }
                }
        }
        
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
        if let originalURL {
            try? FileManager.default.removeItem(at: originalURL)
        }
        self.fullImageCache.removeObject(forKey: id as NSString)
        self.thumbnailCache.removeAllObjects()
        self.notifyChanged()
    }
    
    
    // MARK: - Non-Destructive Image Crop, Zoom, Pan & Aspect Editing
    
    /// Updates an asset's framing/crop/aspect edit and/or title while preserving the untouched original master file.
    @discardableResult
    func updateAssetEdit(
        id: String,
        kind: UserMediaKind,
        title: String? = nil,
        editSpec: UserMediaEditSpec,
        wallpaperManager: WallpaperManager = .shared
    ) -> UserMediaAsset? {
        guard let existing = self.asset(id: id, kind: kind) else { return nil }
        let clampedSpec = editSpec.clamped()
        let activeURL = self.fileURL(for: existing)
        
        // Preserve untouched original master once before baking edits.
        var preservedOriginalName = existing.originalFilename
        if preservedOriginalName == nil {
            let origDir = self.originalsDirectory(for: kind)
            try? FileManager.default.createDirectory(at: origDir, withIntermediateDirectories: true)
            let origURL = origDir.appending(path: existing.filename)
            if !FileManager.default.fileExists(atPath: origURL.path(percentEncoded: false)) {
                try? FileManager.default.copyItem(at: activeURL, to: origURL)
            }
            if FileManager.default.fileExists(atPath: origURL.path(percentEncoded: false)) {
                preservedOriginalName = existing.filename
            }
        }
        
        let masterURL = preservedOriginalName.map { self.originalsDirectory(for: kind).appending(path: $0) } ?? activeURL
        let maxDim: CGFloat = (kind == .avatar) ? 640 : 2400
        guard let sourceCG = Self.normalizedCGImage(fromURL: masterURL, maxDimension: maxDim),
              let renderedCG = Self.renderEditedCGImage(from: sourceCG, spec: clampedSpec, maxOutputSide: maxDim),
              let encoded = Self.encodeNormalizedImage(renderedCG, kind: kind, maxDimension: maxDim)
        else { return nil }
        
        do {
            try encoded.data.write(to: activeURL, options: .atomic)
        } catch {
            return nil
        }
        
        let resolvedTitle: String = {
            if let raw = title?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return raw
            }
            return existing.title
        }()
        
        var updated = existing
        updated.title = resolvedTitle
        updated.pixelWidth = encoded.width
        updated.pixelHeight = encoded.height
        updated.editSpec = clampedSpec.isIdentity ? nil : clampedSpec
        updated.originalFilename = preservedOriginalName
        
        switch kind {
            case .avatar:
                if let idx = self.avatars.firstIndex(where: { $0.id == id }) {
                    self.avatars[idx] = updated
                    self.persistCatalog(for: .avatar)
                }
            case .background:
                if let idx = self.backgrounds.firstIndex(where: { $0.id == id }) {
                    self.backgrounds[idx] = updated
                    self.persistCatalog(for: .background)
                }
                let libWallpaperID = WallpaperManager.mediaLibraryWallpaperID(for: id)
                if wallpaperManager.customRecords.contains(where: { $0.id == libWallpaperID }) {
                    _ = wallpaperManager.refreshMediaLibraryBackground(assetID: id, title: updated.title, fileURL: activeURL)
                }
        }
        
        self.fullImageCache.removeObject(forKey: id as NSString)
        self.thumbnailCache.removeAllObjects()
        self.notifyChanged()
        return updated
    }
    
    
    /// Computes the aspect-fill + zoom/pan draw rect for both SwiftUI preview (`isFlippedY == true`)
    /// and unflipped CoreGraphics/AppKit bitmap rendering (`isFlippedY == false`).
    nonisolated static func cropDrawRect(
        imageSize: CGSize,
        viewportSize: CGSize,
        scale: Double,
        panX: Double,
        panY: Double,
        isFlippedY: Bool
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0
        else { return .zero }
        
        let clampedScale = max(1.0, min(4.0, scale))
        let clampedPanX = max(-1.0, min(1.0, panX))
        let clampedPanY = max(-1.0, min(1.0, panY))
        
        let baseScale = max(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
        let drawW = imageSize.width * baseScale * CGFloat(clampedScale)
        let drawH = imageSize.height * baseScale * CGFloat(clampedScale)
        let slackX = max(0, (drawW - viewportSize.width) * 0.5)
        let slackY = max(0, (drawH - viewportSize.height) * 0.5)
        
        let originX = (viewportSize.width - drawW) * 0.5 - CGFloat(clampedPanX) * slackX
        let ySign: CGFloat = isFlippedY ? -1.0 : 1.0
        let originY = (viewportSize.height - drawH) * 0.5 + ySign * CGFloat(clampedPanY) * slackY
        return CGRect(x: originX, y: originY, width: drawW, height: drawH)
    }
    
    
    /// Renders an edited `CGImage` applying rotation, horizontal flip, aspect-ratio crop, zoom, and pan.
    nonisolated static func renderEditedCGImage(
        from sourceCG: CGImage,
        spec: UserMediaEditSpec,
        maxOutputSide: CGFloat
    ) -> CGImage? {
        let clamped = spec.clamped()
        guard let oriented = Self.orientedCGImage(sourceCG, quarterTurns: clamped.quarterTurns, flipHorizontal: clamped.flipHorizontal) else {
            return nil
        }
        let ow = CGFloat(oriented.width)
        let oh = CGFloat(oriented.height)
        guard ow > 0, oh > 0 else { return nil }
        
        let targetAspect = clamped.aspectPreset.aspectRatio ?? (ow / oh)
        let longestSource = max(ow, oh)
        let cappedLongest = min(maxOutputSide, max(longestSource, 512))
        
        let outW: Int
        let outH: Int
        if targetAspect >= 1.0 {
            outW = max(32, Int(cappedLongest.rounded()))
            outH = max(32, Int((cappedLongest / targetAspect).rounded()))
        } else {
            outH = max(32, Int(cappedLongest.rounded()))
            outW = max(32, Int((cappedLongest * targetAspect).rounded()))
        }
        
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        ctx.interpolationQuality = .high
        let drawRect = Self.cropDrawRect(
            imageSize: CGSize(width: ow, height: oh),
            viewportSize: CGSize(width: CGFloat(outW), height: CGFloat(outH)),
            scale: clamped.scale,
            panX: clamped.panX,
            panY: clamped.panY,
            isFlippedY: false
        )
        ctx.draw(oriented, in: drawRect)
        return ctx.makeImage()
    }
    
    
    nonisolated static func orientedCGImage(_ source: CGImage, quarterTurns: Int, flipHorizontal: Bool) -> CGImage? {
        let turns = ((quarterTurns % 4) + 4) % 4
        if turns == 0 && !flipHorizontal {
            return source
        }
        let sw = CGFloat(source.width)
        let sh = CGFloat(source.height)
        let swapAxes = (turns % 2 == 1)
        let outW = Int(swapAxes ? sh : sw)
        let outH = Int(swapAxes ? sw : sh)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: max(1, outW),
            height: max(1, outH),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        ctx.interpolationQuality = .high
        ctx.translateBy(x: CGFloat(outW) * 0.5, y: CGFloat(outH) * 0.5)
        if flipHorizontal {
            ctx.scaleBy(x: -1, y: 1)
        }
        // Clockwise rotation in unflipped CG coordinates is negative radians.
        ctx.rotate(by: -CGFloat(turns) * (.pi * 0.5))
        ctx.draw(source, in: CGRect(x: -sw * 0.5, y: -sh * 0.5, width: sw, height: sh))
        return ctx.makeImage()
    }
    
    
    // MARK: - One-Click Assignments
    
    @discardableResult
    func applyAvatar(assetID: String, to botID: AIBotID, botStore: AIBotStore = .shared) -> Bool {
        guard let asset = self.asset(id: assetID, kind: .avatar) else { return false }
        let url = self.fileURL(for: asset)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return false }
        botStore.setCustomAvatarData(data, for: botID)
        return true
    }
    
    
    @discardableResult
    func applyAvatarToActiveUser(assetID: String, profileManager: UserProfileManager = .shared) -> Bool {
        guard let asset = self.asset(id: assetID, kind: .avatar),
              let image = self.fullImage(for: asset),
              let pngData = UserProfileManager.processedAvatarPNGData(from: image)
        else { return false }
        profileManager.updateProfile(id: profileManager.activeProfile.id, avatarData: .some(pngData))
        return true
    }
    
    
    @discardableResult
    func applyBackgroundToEditorWallpaper(assetID: String, wallpaperManager: WallpaperManager = .shared) -> Bool {
        guard let asset = self.asset(id: assetID, kind: .background) else { return false }
        let url = self.fileURL(for: asset)
        return wallpaperManager.selectMediaLibraryBackground(assetID: asset.id, title: asset.title, fileURL: url) != nil
    }
    
    
    @discardableResult
    func applyBackgroundToDashboardHero(assetID: String, heroStore: DashboardHeroCoverStore = .shared) -> Bool {
        guard let asset = self.asset(id: assetID, kind: .background) else { return false }
        let url = self.fileURL(for: asset)
        return heroStore.setCoverImage(from: url)
    }
    
    
    func boardAssignment(for slot: BoardBackgroundSlot) -> BoardBackgroundAssignment? {
        guard let assignment = self.boardAssignments[slot.rawValue],
              self.asset(id: assignment.assetID, kind: .background) != nil
        else { return nil }
        return assignment
    }
    
    
    func boardBackgroundAsset(for slot: BoardBackgroundSlot) -> UserMediaAsset? {
        guard let assignment = self.boardAssignment(for: slot) else { return nil }
        return self.asset(id: assignment.assetID, kind: .background)
    }
    
    
    func boardBackgroundImage(for slot: BoardBackgroundSlot) -> NSImage? {
        guard let asset = self.boardBackgroundAsset(for: slot) else { return nil }
        return self.fullImage(for: asset)
    }
    
    
    func assignedBoardSlots(forBackgroundID assetID: String) -> [BoardBackgroundSlot] {
        BoardBackgroundSlot.allCases.filter { self.boardAssignment(for: $0)?.assetID == assetID }
    }
    
    
    func setBoardBackground(
        assetID: String?,
        for slot: BoardBackgroundSlot,
        opacity: Double? = nil,
        blurRadius: Double? = nil
    ) {
        if let assetID, self.asset(id: assetID, kind: .background) != nil {
            let existing = self.boardAssignments[slot.rawValue]
            let next = BoardBackgroundAssignment(
                assetID: assetID,
                opacity: opacity ?? existing?.opacity ?? 0.24,
                blurRadius: blurRadius ?? existing?.blurRadius ?? 10.0
            ).clamped()
            self.boardAssignments[slot.rawValue] = next
        } else {
            self.boardAssignments.removeValue(forKey: slot.rawValue)
        }
        self.persistBoardAssignments()
        self.notifyChanged()
    }
    
    
    func updateBoardBackgroundStyle(for slot: BoardBackgroundSlot, opacity: Double, blurRadius: Double) {
        guard var assignment = self.boardAssignments[slot.rawValue] else { return }
        assignment.opacity = opacity
        assignment.blurRadius = blurRadius
        self.boardAssignments[slot.rawValue] = assignment.clamped()
        self.persistBoardAssignments()
        self.notifyChanged()
    }
    
    
    // MARK: - Private Helpers
    
    private func storeEncodedAsset(
        data: Data,
        fileExtension: String,
        width: Int,
        height: Int,
        hash: String,
        title: String,
        kind: UserMediaKind
    ) -> UserMediaAsset? {
        let dir = self.directory(for: kind)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        
        let prefix = (kind == .avatar) ? "av" : "bg"
        let id = "\(prefix)-\(UUID().uuidString.prefix(10).lowercased())"
        let filename = "\(id).\(fileExtension)"
        let destURL = dir.appending(path: filename)
        do {
            try data.write(to: destURL, options: .atomic)
        } catch {
            return nil
        }
        
        let asset = UserMediaAsset(
            id: id,
            kind: kind,
            title: title,
            filename: filename,
            contentSHA256: hash,
            pixelWidth: width,
            pixelHeight: height,
            createdAt: Date()
        )
        
        switch kind {
            case .avatar:
                self.avatars.insert(asset, at: 0)
            case .background:
                self.backgrounds.insert(asset, at: 0)
        }
        self.persistCatalog(for: kind)
        self.notifyChanged()
        return asset
    }
    
    
    private func persistCatalog(for kind: UserMediaKind) {
        let encoder = JSONEncoder()
        switch kind {
            case .avatar:
                guard let data = try? encoder.encode(self.avatars),
                      let json = String(data: data, encoding: .utf8)
                else { return }
                self.database.set(json, forKey: CotLocalDatabase.ConfigKey.userAvatarLibraryJSON)
            case .background:
                guard let data = try? encoder.encode(self.backgrounds),
                      let json = String(data: data, encoding: .utf8)
                else { return }
                self.database.set(json, forKey: CotLocalDatabase.ConfigKey.userBackgroundLibraryJSON)
        }
    }
    
    
    private func persistBoardAssignments() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self.boardAssignments),
              let json = String(data: data, encoding: .utf8)
        else { return }
        self.database.set(json, forKey: CotLocalDatabase.ConfigKey.boardBackgroundAssignmentsJSON)
    }
    
    
    private func notifyChanged() {
        self.revision &+= 1
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
    
    
    nonisolated static func isSupportedImageURL(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.isEmpty || name.hasPrefix(".") {
            return false
        }
        return Self.supportedImageExtensions.contains(url.pathExtension.lowercased())
    }
    
    
    nonisolated static func inferredKind(forFolderNames folderNames: [String], fallback: UserMediaKind) -> UserMediaKind {
        for rawName in folderNames.reversed() {
            let lower = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if Self.avatarFolderNames.contains(lower) {
                return .avatar
            }
            if Self.backgroundFolderNames.contains(lower) {
                return .background
            }
        }
        return fallback
    }
    
    
    private nonisolated static func collectImagesFromDirectory(
        _ rootURL: URL,
        fallbackKind: UserMediaKind
    ) -> [(url: URL, kind: UserMediaKind)] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        
        let rootName = rootURL.lastPathComponent
        let rootDepth = rootURL.standardizedFileURL.pathComponents.count
        var discovered: [(url: URL, kind: UserMediaKind)] = []
        
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { continue }
            guard Self.isSupportedImageURL(fileURL) else { continue }
            
            let fileParentComponents = fileURL.deletingLastPathComponent().standardizedFileURL.pathComponents
            let relativeDirs = Array(fileParentComponents.dropFirst(min(rootDepth, fileParentComponents.count)))
            let resolvedKind = Self.inferredKind(
                forFolderNames: [rootName] + relativeDirs,
                fallback: fallbackKind
            )
            discovered.append((fileURL, resolvedKind))
        }
        
        discovered.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        return discovered
    }
    
    
    private nonisolated static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    
    private nonisolated static func normalizedCGImage(fromURL url: URL, maxDimension: CGFloat) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return Self.normalizedCGImage(fromSource: src, maxDimension: maxDimension)
    }
    
    
    private nonisolated static func normalizedCGImage(fromData data: Data, maxDimension: CGFloat) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return Self.normalizedCGImage(fromSource: src, maxDimension: maxDimension)
    }
    
    
    private nonisolated static func normalizedCGImage(fromSource src: CGImageSource, maxDimension: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) {
            return thumb
        }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
    
    
    private static func underlyingCGImage(from image: NSImage) -> CGImage? {
        if let direct = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return direct
        }
        var proposed = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }
    
    
    private nonisolated static func encodeNormalizedImage(
        _ cgImage: CGImage,
        kind: UserMediaKind,
        maxDimension: CGFloat? = nil
    ) -> (data: Data, fileExtension: String, width: Int, height: Int)? {
        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        guard srcW > 0, srcH > 0 else { return nil }
        
        let cap = maxDimension ?? (kind == .avatar ? 512 : 2400)
        let scale = min(1.0, cap / max(srcW, srcH))
        let dstW = max(1, Int((srcW * scale).rounded()))
        let dstH = max(1, Int((srcH * scale).rounded()))
        
        let alpha = cgImage.alphaInfo
        let hasAlpha = (kind == .avatar)
            && alpha != .none
            && alpha != .noneSkipFirst
            && alpha != .noneSkipLast
        
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: dstW,
            height: dstH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))
        guard let renderedCG = ctx.makeImage() else { return nil }
        
        let rep = NSBitmapImageRep(cgImage: renderedCG)
        if hasAlpha, let pngData = rep.representation(using: .png, properties: [:]) {
            return (pngData, "png", dstW, dstH)
        }
        let quality: Double = (kind == .avatar) ? 0.90 : 0.88
        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            return nil
        }
        return (jpegData, "jpg", dstW, dstH)
    }
    
    
    private static func estimatedCost(of image: NSImage) -> Int {
        if let cg = self.underlyingCGImage(from: image) {
            return max(4096, cg.bytesPerRow * cg.height)
        }
        return max(4096, Int(image.size.width * image.size.height * 16))
    }
}
