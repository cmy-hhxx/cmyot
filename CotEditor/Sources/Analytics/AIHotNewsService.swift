//
//  AIHotNewsService.swift
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

/// Editorial category for the Dashboard NEWS stream (Finance, X / Social signals, AI & Tech).
nonisolated enum NewsFeedCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    
    case all
    case finance
    case xSocial
    case ai
    
    var id: String { self.rawValue }
    
    var label: String {
        switch self {
            case .all: AppLanguage.text("全部", en: "All")
            case .finance: AppLanguage.text("金融", en: "Finance")
            case .xSocial: AppLanguage.text("X 动态", en: "X")
            case .ai: "AI"
        }
    }
    
    var badgeLabel: String {
        switch self {
            case .all: ""
            case .finance: AppLanguage.text("金融", en: "Finance")
            case .xSocial: "X"
            case .ai: "AI"
        }
    }
}


/// A single industry news item displayed in the Analytics Dashboard NEWS feed.
nonisolated struct AIHotNewsItem: Identifiable, Codable, Hashable, Sendable {
    
    var id: String
    var title: String
    var source: String
    var urlString: String
    var publishedAt: Date?
    var heatScore: Int?
    var tag: String?
    var coverURLString: String? = nil
    var category: NewsFeedCategory? = nil
    
    var resolvedCategory: NewsFeedCategory {
        if let category, category != .all {
            return category
        }
        let haystack = "\(self.source) \(self.tag ?? "") \(self.title) \(self.urlString)".lowercased()
        if haystack.contains("x.com") || haystack.contains("twitter") || haystack.contains("x 热议") || haystack.contains("x 动态") {
            return .xSocial
        }
        if haystack.contains("cnbc") || haystack.contains("wsj") || haystack.contains("yahoo") || haystack.contains("investing")
            || haystack.contains("bloomberg") || haystack.contains("reuters") || haystack.contains("财经")
            || haystack.contains("金融") || haystack.contains("美股") || haystack.contains("美联储") || haystack.contains("market")
            || haystack.contains("fed") || haystack.contains("stock") || haystack.contains("nasdaq")
        {
            return .finance
        }
        return .ai
    }
    
    var url: URL? {
        guard let sanitized = AIHotNewsService.sanitizedHTTPURLString(self.urlString) else { return nil }
        return URL(string: sanitized)
    }
    
    var coverURL: URL? {
        guard let sanitized = AIHotNewsService.sanitizedHTTPURLString(self.coverURLString) else { return nil }
        return URL(string: sanitized)
    }
    
    
    /// Short, pill-free metadata string (never displays `ai.hot` / `aihot.news`).
    var conciseMetaLabel: String {
        var parts: [String] = []
        let cleanSource = AIHotNewsService.sanitizedDisplaySource(self.source)
        if !cleanSource.isEmpty {
            parts.append(cleanSource)
        }
        if let score = self.heatScore, score > 0 {
            parts.append("\(score)°")
        } else if let tag = self.tag, !tag.isEmpty, !tag.lowercased().contains("aihot") {
            parts.append(tag)
        }
        return parts.joined(separator: " · ")
    }
}


/// Multi-source live news aggregator for the Analytics Dashboard's NEWS column:
/// Finance / Markets (CNBC, Yahoo Finance, WSJ, Investing, 全球财经), X / Social Tech signals, and AI & Tech,
/// with Xiaohongshu-style pagination, category filter, and real post cover thumbnails (`og:image` / feed covers).
@MainActor @Observable
final class AIHotNewsService {
    
    static let shared = AIHotNewsService()
    /// Retained strictly as relative-URL parser fallback for backward compatibility; never shown in UI.
    nonisolated static let portalURL = URL(string: "https://aihot.news/agent")!
    static let pageSize = 6
    
    private struct FeedSource: Sendable {
        let urlString: String
        let label: String
        let category: NewsFeedCategory
        let isHNJSON: Bool
    }
    
    private static let cacheTTL: TimeInterval = 5 * 60
    private static let feedSources: [FeedSource] = [
        // Finance & Markets (金融类)
        .init(urlString: "https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=10000664", label: "CNBC 财经", category: .finance, isHNJSON: false),
        .init(urlString: "https://finance.yahoo.com/news/rssindex", label: "Yahoo Finance", category: .finance, isHNJSON: false),
        .init(urlString: "https://feeds.content.dowjones.io/public/rss/RSSMarketsMain", label: "WSJ Markets", category: .finance, isHNJSON: false),
        .init(urlString: "https://www.investing.com/rss/news.rss", label: "Investing", category: .finance, isHNJSON: false),
        .init(urlString: "https://news.google.com/rss/search?q=%E7%BE%8E%E8%82%A1+OR+%E7%BE%8E%E8%81%94%E5%82%A8+OR+A%E8%82%A1+OR+%E9%87%91%E8%9E%8D&hl=zh-CN&gl=CN&ceid=CN:zh-Hans", label: "全球财经", category: .finance, isHNJSON: false),
        // X (Twitter) & Social Creator Signals (X 动态)
        .init(urlString: "https://hn.algolia.com/api/v1/search_by_date?query=x.com&tags=story&hitsPerPage=14", label: "X 热议", category: .xSocial, isHNJSON: true),
        .init(urlString: "https://news.google.com/rss/search?q=site:x.com+OR+Twitter+AI+OR+Markets&hl=zh-CN&gl=CN&ceid=CN:zh-Hans", label: "X 动态", category: .xSocial, isHNJSON: false),
        .init(urlString: "https://hn.algolia.com/api/v1/search?tags=front_page&hitsPerPage=14", label: "HN / X", category: .xSocial, isHNJSON: true),
        // AI & Tech (AI 科技)
        .init(urlString: "https://techcrunch.com/category/artificial-intelligence/feed/", label: "TechCrunch AI", category: .ai, isHNJSON: false),
        .init(urlString: "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml", label: "The Verge AI", category: .ai, isHNJSON: false),
        .init(urlString: "https://huggingface.co/blog/feed.xml", label: "Hugging Face", category: .ai, isHNJSON: false),
    ]
    
    private(set) var items: [AIHotNewsItem] = []
    private(set) var isLoading = false
    private(set) var lastUpdatedAt: Date?
    private(set) var loadFailed = false
    private(set) var currentPage: Int = 1
    var selectedCategory: NewsFeedCategory = .all {
        didSet {
            guard self.selectedCategory != oldValue else { return }
            self.currentPage = 1
            self.prefetchCoversForCurrentPage()
        }
    }
    private(set) var coverImages: [String: NSImage] = [:]
    
    private var inFlightCoverIDs: Set<String> = []
    private var resolvedNoCoverIDs: Set<String> = []
    private let coverCacheDirectory: URL
    
    
    var filteredItems: [AIHotNewsItem] {
        guard self.selectedCategory != .all else { return self.items }
        return self.items.filter { $0.resolvedCategory == self.selectedCategory }
    }
    
    
    var totalPages: Int {
        max(1, Int(ceil(Double(self.filteredItems.count) / Double(Self.pageSize))))
    }
    
    
    var currentPageItems: [AIHotNewsItem] {
        let pool = self.filteredItems
        guard !pool.isEmpty else { return [] }
        let safePage = min(max(1, self.currentPage), self.totalPages)
        let start = (safePage - 1) * Self.pageSize
        guard start < pool.count else { return [] }
        let end = min(pool.count, start + Self.pageSize)
        return Array(pool[start..<end])
    }
    
    
    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        self.coverCacheDirectory = caches
            .appending(path: "CotEditor", directoryHint: .isDirectory)
            .appending(path: "NewsCovers", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: self.coverCacheDirectory, withIntermediateDirectories: true)
        self.loadCachedItems()
    }
    
    
    func goToNextPage() {
        guard self.totalPages > 1 else { return }
        self.currentPage = (self.currentPage >= self.totalPages) ? 1 : (self.currentPage + 1)
        self.prefetchCoversForCurrentPage()
    }
    
    
    func goToPreviousPage() {
        guard self.totalPages > 1 else { return }
        self.currentPage = (self.currentPage <= 1) ? self.totalPages : (self.currentPage - 1)
        self.prefetchCoversForCurrentPage()
    }
    
    
    func goToPage(_ page: Int) {
        self.currentPage = min(max(1, page), self.totalPages)
        self.prefetchCoversForCurrentPage()
    }
    
    
    func coverImage(for item: AIHotNewsItem) -> NSImage? {
        if let cached = self.coverImages[item.id] {
            return cached
        }
        let diskURL = self.diskCoverURL(for: item)
        if let diskImage = NSImage(contentsOf: diskURL) {
            self.coverImages[item.id] = diskImage
            return diskImage
        }
        self.triggerCoverLoadIfNeeded(for: item)
        return nil
    }
    
    
    func prefetchCoversForCurrentPage() {
        for item in self.currentPageItems {
            _ = self.coverImage(for: item)
        }
    }
    
    
    /// Refreshes multi-category news (Finance, X / Social signals, AI & Tech) concurrently when stale or forced.
    func refreshIfNeeded(force: Bool = false) async {
        
        guard !self.isLoading else { return }
        if !force,
           let lastUpdatedAt = self.lastUpdatedAt,
           Date().timeIntervalSince(lastUpdatedAt) < Self.cacheTTL,
           !self.items.isEmpty
        {
            self.prefetchCoversForCurrentPage()
            return
        }
        
        self.isLoading = true
        defer { self.isLoading = false }
        
        let sources = Self.feedSources
        var buckets: [NewsFeedCategory: [AIHotNewsItem]] = [
            .finance: [],
            .xSocial: [],
            .ai: [],
        ]
        
        await withTaskGroup(of: (NewsFeedCategory, [AIHotNewsItem]).self) { group in
            for feed in sources {
                group.addTask {
                    let fetched = await Self.fetchSingleFeed(feed)
                    return (feed.category, fetched)
                }
            }
            for await (cat, batch) in group {
                buckets[cat, default: []].append(contentsOf: batch)
            }
        }
        
        guard !Task.isCancelled else { return }
        
        // Round-robin interleave across Finance -> X -> AI so every page has balanced multi-sector news
        let order: [NewsFeedCategory] = [.finance, .xSocial, .ai]
        var cursors: [NewsFeedCategory: Int] = [.finance: 0, .xSocial: 0, .ai: 0]
        var seenTitles = Set<String>()
        var mergedItems: [AIHotNewsItem] = []
        
        while mergedItems.count < 48 {
            var progressed = false
            for cat in order {
                let list = buckets[cat] ?? []
                var idx = cursors[cat] ?? 0
                while idx < list.count {
                    let item = list[idx]
                    idx += 1
                    let key = item.title.lowercased()
                    guard !Self.containsBlockedBrand(item), seenTitles.insert(key).inserted else { continue }
                    mergedItems.append(item)
                    progressed = true
                    break
                }
                cursors[cat] = idx
                if mergedItems.count >= 48 { break }
            }
            if !progressed { break }
        }
        
        if !mergedItems.isEmpty {
            self.items = mergedItems
            if force {
                self.currentPage = 1
                self.resolvedNoCoverIDs.removeAll()
            } else {
                self.currentPage = min(max(1, self.currentPage), self.totalPages)
            }
            self.lastUpdatedAt = Date()
            self.loadFailed = false
            self.saveCachedItems(mergedItems)
            self.prefetchCoversForCurrentPage()
        } else {
            self.loadFailed = self.items.isEmpty
        }
    }
    
    
    private nonisolated static func fetchSingleFeed(_ feed: FeedSource) async -> [AIHotNewsItem] {
        guard let url = URL(string: feed.urlString) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "application/json, application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  !data.isEmpty
            else { return [] }
            
            var parsed: [AIHotNewsItem]
            if feed.isHNJSON {
                parsed = Self.parseHackerNewsAlgoliaJSON(data, defaultSource: feed.label, category: feed.category)
            } else {
                parsed = Self.parseRSS(data)
            }
            
            return parsed.prefix(12).map { item in
                var tagged = item
                tagged.category = feed.category
                if tagged.source.isEmpty || tagged.source.lowercased().contains("google") || tagged.source.lowercased().contains("aihot") {
                    tagged.source = feed.label
                }
                if tagged.tag == nil || tagged.tag?.isEmpty == true {
                    tagged.tag = feed.category.badgeLabel
                }
                return tagged
            }
        } catch {
            return []
        }
    }
    
    
    /// Parses Hacker News Algolia search JSON (`{"hits": [...]}`) into `AIHotNewsItem` entries.
    nonisolated static func parseHackerNewsAlgoliaJSON(
        _ data: Data,
        defaultSource: String = "X / HN",
        category: NewsFeedCategory = .xSocial
    ) -> [AIHotNewsItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = root["hits"] as? [[String: Any]]
        else { return [] }
        
        var results: [AIHotNewsItem] = []
        var seen = Set<String>()
        for (idx, hit) in hits.enumerated() {
            guard let rawTitle = (hit["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  rawTitle.count >= 4
            else { continue }
            
            let rawURL = (hit["url"] as? String)
                ?? (hit["objectID"] as? String).map { "https://news.ycombinator.com/item?id=\($0)" }
            guard let safeURL = Self.sanitizedHTTPURLString(rawURL) else { continue }
            let dedupe = rawTitle.lowercased()
            guard seen.insert(dedupe).inserted else { continue }
            
            let host = Self.hostLabel(from: safeURL)
            let isXLink = host.contains("x.com") || host.contains("twitter.com")
            let displaySource = isXLink ? "X (@\(Self.extractXHandle(from: safeURL) ?? "x.com"))" : (host.isEmpty ? defaultSource : host)
            let points = hit["points"] as? Int
            let itemID = (hit["objectID"] as? String) ?? "hn-\(idx)-\(dedupe.prefix(18))"
            let publishedAt = (hit["created_at"] as? String).flatMap { Self.parseDateString($0) }
            
            results.append(AIHotNewsItem(
                id: itemID,
                title: rawTitle,
                source: displaySource,
                urlString: safeURL,
                publishedAt: publishedAt,
                heatScore: points,
                tag: isXLink ? "X" : category.badgeLabel,
                coverURLString: nil,
                category: category
            ))
        }
        return results
    }
    
    
    private nonisolated static func extractXHandle(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let first = segments.first,
              !["i", "search", "explore", "home", "hashtag", "intent"].contains(first.lowercased())
        else { return nil }
        return first
    }
    
    
    nonisolated static func containsBlockedBrand(_ item: AIHotNewsItem) -> Bool {
        let lowerSource = item.source.lowercased()
        let lowerURL = item.urlString.lowercased()
        return lowerSource.contains("aihot") || lowerSource.contains("ai.hot")
            || lowerURL.contains("aihot.news") || lowerURL.contains("ai.hot")
    }
    
    
    nonisolated static func sanitizedDisplaySource(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.contains("aihot") || lower.contains("ai.hot") {
            return "News"
        }
        return trimmed
    }
    
    
    // MARK: Real Post Cover Thumbnail Loader (Feed Cover + og:image Fallback)
    
    private func diskCoverURL(for item: AIHotNewsItem) -> URL {
        let digest = SHA256.hash(data: Data((item.coverURLString ?? item.urlString).utf8))
        let hex = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return self.coverCacheDirectory.appending(path: "\(hex).jpg")
    }
    
    
    private func triggerCoverLoadIfNeeded(for item: AIHotNewsItem) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              !self.inFlightCoverIDs.contains(item.id),
              !self.resolvedNoCoverIDs.contains(item.id)
        else { return }
        
        let itemID = item.id
        let directCoverURL = item.coverURL
        let pageURL = item.url
        let diskURL = self.diskCoverURL(for: item)
        self.inFlightCoverIDs.insert(itemID)
        
        Task.detached(priority: .utility) {
            var resolvedImageURL = directCoverURL
            if resolvedImageURL == nil, let pageURL {
                resolvedImageURL = await Self.fetchOpenGraphCoverURL(from: pageURL)
            }
            
            guard let imgURL = resolvedImageURL else {
                await MainActor.run {
                    _ = AIHotNewsService.shared.inFlightCoverIDs.remove(itemID)
                    _ = AIHotNewsService.shared.resolvedNoCoverIDs.insert(itemID)
                }
                return
            }
            
            var req = URLRequest(url: imgURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
            req.setValue("image/webp,image/jpeg,image/png,image/*;q=0.8", forHTTPHeaderField: "Accept")
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            
            guard let (data, response) = try? await URLSession.shared.data(for: req),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count > 256,
                  let thumbnail = Self.downsampledThumbnail(from: data, maxPixelSize: 320)
            else {
                await MainActor.run {
                    _ = AIHotNewsService.shared.inFlightCoverIDs.remove(itemID)
                    _ = AIHotNewsService.shared.resolvedNoCoverIDs.insert(itemID)
                }
                return
            }
            
            if let tiff = thumbnail.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.78])
            {
                try? jpeg.write(to: diskURL, options: .atomic)
            }
            
            await MainActor.run {
                AIHotNewsService.shared.coverImages[itemID] = thumbnail
                if let idx = AIHotNewsService.shared.items.firstIndex(where: { $0.id == itemID }),
                   AIHotNewsService.shared.items[idx].coverURLString == nil
                {
                    AIHotNewsService.shared.items[idx].coverURLString = imgURL.absoluteString
                }
                _ = AIHotNewsService.shared.inFlightCoverIDs.remove(itemID)
            }
        }
    }
    
    
    private nonisolated static func fetchOpenGraphCoverURL(from pageURL: URL) async -> URL? {
        var req = URLRequest(url: pageURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 6)
        req.setValue("text/html,application/xhtml+xml;q=0.9", forHTTPHeaderField: "Accept")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("bytes=0-32767", forHTTPHeaderField: "Range")
        
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty
        else { return nil }
        
        let snippetData = data.prefix(36_000)
        guard let html = String(data: snippetData, encoding: .utf8) ?? String(data: snippetData, encoding: .isoLatin1),
              let urlString = Self.extractOpenGraphImageURL(from: html, pageURL: pageURL)
        else { return nil }
        return URL(string: urlString)
    }
    
    
    private nonisolated static func downsampledThumbnail(from data: Data, maxPixelSize: CGFloat) -> NSImage? {
        let cfData = data as CFData
        guard let source = CGImageSourceCreateWithData(cfData, nil) else {
            return NSImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
    
    
    // MARK: Persistence
    
    private func loadCachedItems() {
        
        let raw = CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.aiHotNewsCacheJSON, default: "")
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return }
        if let decoded = try? JSONDecoder().decode([AIHotNewsItem].self, from: data) {
            let cleaned = decoded.filter { !Self.containsBlockedBrand($0) }
            if !cleaned.isEmpty {
                self.items = cleaned
            }
        }
    }
    
    
    private func saveCachedItems(_ items: [AIHotNewsItem]) {
        
        guard let encoded = try? JSONEncoder().encode(items),
              let string = String(data: encoded, encoding: .utf8)
        else { return }
        CotLocalDatabase.shared.set(string, forKey: CotLocalDatabase.ConfigKey.aiHotNewsCacheJSON)
    }
    
    
    // MARK: Pure Parsers (Testable & Nonisolated)
    
    nonisolated static func parseJSON(_ data: Data) -> [AIHotNewsItem] {
        
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let rawObjects = Self.extractItemDictionaries(from: root)
        guard !rawObjects.isEmpty else { return [] }
        
        var seenTitles = Set<String>()
        var seenIDs = Set<String>()
        var results: [AIHotNewsItem] = []
        
        for (index, dict) in rawObjects.enumerated() {
            guard let rawTitle = Self.firstString(in: dict, keys: ["title", "headline", "name", "subject"]),
                  !rawTitle.isEmpty
            else { continue }
            
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let directURL = Self.firstString(in: dict, keys: ["url", "link", "source_url", "sourceUrl", "href", "canonical_url"])
            let fallbackSlug = Self.firstString(in: dict, keys: ["slug", "id"])
            let resolvedURL: String
            if let sanitized = Self.sanitizedHTTPURLString(directURL) {
                resolvedURL = sanitized
            } else if let fallbackSlug,
                      !fallbackSlug.isEmpty,
                      let encodedSlug = fallbackSlug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            {
                resolvedURL = "https://aihot.news/items/\(encodedSlug)"
            } else {
                resolvedURL = Self.portalURL.absoluteString
            }
            
            let explicitSource = Self.firstString(in: dict, keys: ["source", "source_name", "sourceName", "domain", "site", "publisher", "author"])
            let source = (explicitSource.flatMap { $0.isEmpty ? nil : $0 }) ?? Self.hostLabel(from: resolvedURL)
            let heatScore = Self.firstInt(in: dict, keys: ["heat", "heat_score", "heatScore", "score", "points", "upvotes", "hot"])
            let tag = Self.firstString(in: dict, keys: ["tag", "category", "topic", "cluster"])
            let publishedAt = Self.firstDate(in: dict, keys: ["published_at", "publishedAt", "created_at", "createdAt", "date", "timestamp", "time"])
            let baseID = Self.firstString(in: dict, keys: ["id", "guid", "slug"]) ?? "\(resolvedURL)#\(index)"
            let itemID = seenIDs.contains(baseID) ? "\(baseID)#\(index)" : baseID
            
            let dedupeKey = title.lowercased()
            guard seenTitles.insert(dedupeKey).inserted else { continue }
            seenIDs.insert(itemID)
            
            let rawCover = Self.extractCoverURLString(from: dict)
            let coverURLString = Self.sanitizedHTTPURLString(rawCover)
            
            results.append(AIHotNewsItem(
                id: itemID,
                title: title,
                source: source,
                urlString: resolvedURL,
                publishedAt: publishedAt,
                heatScore: heatScore,
                tag: tag,
                coverURLString: coverURLString
            ))
        }
        
        return results
    }
    
    
    nonisolated static func parseAgentMarkdown(_ text: String) -> [AIHotNewsItem] {
        
        let linkRegex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^\s\)]+)\)"#)
        let bareURLRegex = try? NSRegularExpression(pattern: #"https?://[^\s\)\]>]+"#)
        
        var seen = Set<String>()
        var results: [AIHotNewsItem] = []
        
        for (idx, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard !line.hasPrefix("```"), !line.hasPrefix("---"), !line.hasPrefix("<!--") else { continue }
            
            // Skip plain frontmatter metadata keys like `updated_at: ...`
            if !line.contains("http://") && !line.contains("https://") {
                continue
            }
            
            // Strip bullet / numbering / heading prefix
            line = line.replacingOccurrences(
                of: #"^(?:[-*•]+|\d+[.)]|#+)\s+"#,
                with: "",
                options: .regularExpression
            )
            
            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            
            var title = ""
            var urlString = ""
            var trailingContext = ""
            
            if let linkMatch = linkRegex?.firstMatch(in: line, range: fullRange),
               linkMatch.numberOfRanges >= 3
            {
                title = nsLine.substring(with: linkMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                urlString = nsLine.substring(with: linkMatch.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                let after = NSMaxRange(linkMatch.range)
                if after < nsLine.length {
                    trailingContext = nsLine.substring(from: after)
                }
            } else if let urlMatch = bareURLRegex?.firstMatch(in: line, range: fullRange) {
                urlString = nsLine.substring(with: urlMatch.range)
                let withoutURL = nsLine.replacingCharacters(in: urlMatch.range, with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " -–—|:•·*"))
                title = withoutURL.isEmpty ? Self.hostLabel(from: urlString) : withoutURL
            } else {
                continue
            }
            
            title = title.replacingOccurrences(of: "**", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count >= 4, let sanitizedURL = Self.sanitizedHTTPURLString(urlString) else { continue }
            urlString = sanitizedURL
            
            // Optional `· Source` or `(Source)` extraction from trailing text
            var source = ""
            var heatScore: Int?
            let cleanedTrailing = trailingContext
                .trimmingCharacters(in: CharacterSet(charactersIn: " -–—|:()[]·•"))
            if !cleanedTrailing.isEmpty {
                let tokens = cleanedTrailing
                    .components(separatedBy: CharacterSet(charactersIn: "|·•—"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                for token in tokens {
                    if let parsedHeat = Self.parseHeatToken(token) {
                        heatScore = heatScore ?? parsedHeat
                    } else if Self.isRelativeTimeToken(token) {
                        continue
                    } else if source.isEmpty, token.count <= 24 {
                        source = token
                    }
                }
            }
            if source.isEmpty {
                source = Self.hostLabel(from: urlString)
            }
            
            let dedupe = title.lowercased()
            guard seen.insert(dedupe).inserted else { continue }
            
            results.append(AIHotNewsItem(
                id: "md-\(idx)-\(dedupe.prefix(24))",
                title: title,
                source: source,
                urlString: urlString,
                publishedAt: nil,
                heatScore: heatScore,
                tag: nil
            ))
        }
        
        return results
    }
    
    
    nonisolated static func parseRSS(_ data: Data) -> [AIHotNewsItem] {
        
        let delegate = RSSFeedParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return [] }
        return delegate.items
    }
    
    
    // MARK: Private Parsing Helpers
    
    private nonisolated static func extractItemDictionaries(from root: Any) -> [[String: Any]] {
        
        if let array = root as? [[String: Any]] {
            return array
        }
        guard let dict = root as? [String: Any] else { return [] }
        
        for key in ["items", "stories", "news", "articles", "results", "entries", "data"] {
            if let list = dict[key] as? [[String: Any]], !list.isEmpty {
                return list
            }
        }
        if let nested = dict["data"] as? [String: Any] {
            for key in ["items", "stories", "news", "articles", "results", "entries"] {
                if let list = nested[key] as? [[String: Any]], !list.isEmpty {
                    return list
                }
            }
        }
        return []
    }
    
    
    private nonisolated static func firstString(in dict: [String: Any], keys: [String]) -> String? {
        
        for key in keys {
            if let str = dict[key] as? String {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let num = dict[key] as? NSNumber, !(dict[key] is Bool) {
                return num.stringValue
            }
        }
        return nil
    }
    
    
    private nonisolated static func firstInt(in dict: [String: Any], keys: [String]) -> Int? {
        
        for key in keys {
            if let intVal = dict[key] as? Int {
                return intVal
            }
            if let doubleVal = dict[key] as? Double,
               doubleVal.isFinite,
               doubleVal >= Double(Int.min),
               doubleVal <= Double(Int.max)
            {
                return Int(doubleVal.rounded())
            }
            if let str = dict[key] as? String, let parsed = Int(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return parsed
            }
        }
        return nil
    }
    
    
    private nonisolated static func firstDate(in dict: [String: Any], keys: [String]) -> Date? {
        
        for key in keys {
            if let ts = dict[key] as? Double {
                return ts > 1_000_000_000_000 ? Date(timeIntervalSince1970: ts / 1000.0) : Date(timeIntervalSince1970: ts)
            }
            if let tsInt = dict[key] as? Int {
                let ts = Double(tsInt)
                return ts > 1_000_000_000_000 ? Date(timeIntervalSince1970: ts / 1000.0) : Date(timeIntervalSince1970: ts)
            }
            if let str = dict[key] as? String, let date = Self.parseDateString(str) {
                return date
            }
        }
        return nil
    }
    
    
    fileprivate nonisolated static func parseDateString(_ raw: String) -> Date? {
        
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: trimmed) { return d }
        
        let isoStd = ISO8601DateFormatter()
        isoStd.formatOptions = [.withInternetDateTime]
        if let d = isoStd.date(from: trimmed) { return d }
        
        let rfc822 = DateFormatter()
        rfc822.locale = Locale(identifier: "en_US_POSIX")
        for format in [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
        ] {
            rfc822.dateFormat = format
            if let d = rfc822.date(from: trimmed) { return d }
        }
        return nil
    }
    
    
    /// Validates and normalizes remote news URLs to strictly `http` or `https` with a non-empty host.
    /// Relative paths (e.g. `/items/123`) are resolved against `portalURL`; unsafe schemes (`file:`, `smb:`, `javascript:`) return `nil`.
    nonisolated static func sanitizedHTTPURLString(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        let resolved: URL?
        if trimmed.hasPrefix("/") {
            resolved = URL(string: trimmed, relativeTo: Self.portalURL)?.absoluteURL
        } else {
            resolved = URL(string: trimmed)
        }
        guard let url = resolved,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty
        else { return nil }
        return url.absoluteString
    }
    
    
    private nonisolated static func isRelativeTimeToken(_ token: String) -> Bool {
        let lower = token.lowercased().trimmingCharacters(in: .whitespaces)
        return lower.range(of: #"^\d+\s*(s|sec|secs|m|min|mins|h|hr|hrs|d|w|分钟前|小时前|天前)$"#, options: .regularExpression) != nil
    }
    
    
    private nonisolated static func parseHeatToken(_ token: String) -> Int? {
        guard !Self.isRelativeTimeToken(token) else { return nil }
        let lower = token.lowercased().trimmingCharacters(in: .whitespaces)
        guard lower.range(of: #"^(?:热度\s*)?\d{1,6}(?:\s*(?:°|🔥|pts?|pt|热度))?$"#, options: .regularExpression) != nil else {
            return nil
        }
        return Int(lower.filter(\.isNumber))
    }
    
    
    /// Extracts `og:image`, `twitter:image`, or `<link rel="image_src">` from a post's HTML head.
    nonisolated static func extractOpenGraphImageURL(from html: String, pageURL: URL) -> String? {
        let patterns: [String] = [
            #"<meta[^>]+(?:property|name)\s*=\s*["'](?:og:image:secure_url|og:image|twitter:image:src|twitter:image)["'][^>]+content\s*=\s*["']([^"']+)["']"#,
            #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+(?:property|name)\s*=\s*["'](?:og:image:secure_url|og:image|twitter:image:src|twitter:image)["']"#,
            #"<link[^>]+rel\s*=\s*["']image_src["'][^>]+href\s*=\s*["']([^"']+)["']"#,
        ]
        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            if let match = regex.firstMatch(in: html, range: range), match.numberOfRanges >= 2 {
                let raw = nsHTML.substring(with: match.range(at: 1))
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let resolved = URL(string: raw, relativeTo: pageURL)?.absoluteURL.absoluteString,
                   let sanitized = Self.sanitizedHTTPURLString(resolved)
                {
                    return sanitized
                }
            }
        }
        return nil
    }
    
    
    private nonisolated static func extractCoverURLString(from dict: [String: Any]) -> String? {
        if let direct = Self.firstString(in: dict, keys: [
            "cover", "cover_url", "coverUrl", "image", "image_url", "imageUrl",
            "thumbnail", "thumbnail_url", "thumbnailUrl", "og_image", "ogImage", "banner", "pic",
        ]) {
            return direct
        }
        for nestedKey in ["media", "enclosure", "meta", "og"] {
            if let sub = dict[nestedKey] as? [String: Any],
               let nested = Self.firstString(in: sub, keys: ["url", "image", "cover", "src", "thumbnail"])
            {
                return nested
            }
        }
        if let images = dict["images"] as? [String], let first = images.first {
            return first
        }
        return nil
    }
    
    
    fileprivate nonisolated static func firstHTMLImageURL(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<img[^>]+src\s*=\s*["']([^"']+)["']"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let ns = html as NSString
        if let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
           match.numberOfRanges >= 2
        {
            let raw = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            return Self.sanitizedHTTPURLString(raw)
        }
        return nil
    }
    
    
    fileprivate nonisolated static func hostLabel(from urlString: String) -> String {
        
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else {
            return "News"
        }
        let cleaned = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return (cleaned.contains("aihot") || cleaned.contains("ai.hot")) ? "News" : cleaned
    }
}


private nonisolated final class RSSFeedParserDelegate: NSObject, XMLParserDelegate {
    
    var items: [AIHotNewsItem] = []
    
    private var inEntry = false
    private var elementStack: [String] = []
    private var currentTitle = ""
    private var currentLink = ""
    private var currentSource = ""
    private var currentDate = ""
    private var currentCategory = ""
    private var currentID = ""
    private var currentCover = ""
    private var elementBuffer = ""
    private var seenTitles = Set<String>()
    private var seenIDs = Set<String>()
    
    
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let local = elementName.lowercased()
        self.elementStack.append(local)
        self.elementBuffer = ""
        
        if local == "item" || local == "entry" {
            self.inEntry = true
            self.currentTitle = ""
            self.currentLink = ""
            self.currentSource = ""
            self.currentDate = ""
            self.currentCategory = ""
            self.currentID = ""
            self.currentCover = ""
        } else if self.inEntry {
            if self.isDirectEntryChild,
               local == "link",
               let href = attributeDict["href"],
               !href.isEmpty
            {
                let rel = attributeDict["rel"]?.lowercased()
                if rel == nil || rel == "alternate" || self.currentLink.isEmpty {
                    self.currentLink = href
                }
            } else if self.currentCover.isEmpty,
                      (local == "media:thumbnail" || local == "media:content" || local == "enclosure"),
                      let mediaURL = attributeDict["url"],
                      !mediaURL.isEmpty
            {
                let mime = attributeDict["type"]?.lowercased() ?? ""
                let medium = attributeDict["medium"]?.lowercased() ?? ""
                if local != "enclosure" || mime.hasPrefix("image/") || medium == "image" {
                    self.currentCover = mediaURL
                }
            }
        }
    }
    
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard self.inEntry else { return }
        self.elementBuffer += string
    }
    
    
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard self.inEntry, let decoded = String(data: CDATABlock, encoding: .utf8) else { return }
        self.elementBuffer += decoded
    }
    
    
    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let local = elementName.lowercased()
        let text = self.elementBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = self.elementStack.count >= 2 ? self.elementStack[self.elementStack.count - 2] : ""
        
        if self.inEntry && !text.isEmpty {
            let isEntryDirect = (parent == "item" || parent == "entry")
            if isEntryDirect {
                switch local {
                    case "title":
                        if self.currentTitle.isEmpty { self.currentTitle = text }
                    case "link":
                        if self.currentLink.isEmpty { self.currentLink = text }
                    case "source", "dc:creator", "author":
                        if self.currentSource.isEmpty { self.currentSource = text }
                    case "pubdate", "published", "updated", "dc:date":
                        if self.currentDate.isEmpty { self.currentDate = text }
                    case "category":
                        if self.currentCategory.isEmpty { self.currentCategory = text }
                    case "guid", "id":
                        if self.currentID.isEmpty { self.currentID = text }
                    case "description", "summary", "content", "content:encoded":
                        if self.currentCover.isEmpty, let img = AIHotNewsService.firstHTMLImageURL(in: text) {
                            self.currentCover = img
                        }
                    default:
                        break
                }
            } else if (parent == "author" && local == "name") || (parent == "source" && local == "title") {
                if self.currentSource.isEmpty {
                    self.currentSource = text
                }
            }
        }
        
        if local == "item" || local == "entry", self.inEntry {
            self.inEntry = false
            let title = self.currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                self.popStack()
                return
            }
            let dedupeTitle = title.lowercased()
            if self.seenTitles.insert(dedupeTitle).inserted {
                let resolvedURL = AIHotNewsService.sanitizedHTTPURLString(self.currentLink)
                    ?? AIHotNewsService.portalURL.absoluteString
                let source = self.currentSource.isEmpty
                    ? AIHotNewsService.hostLabel(from: resolvedURL)
                    : self.currentSource
                let publishedAt = AIHotNewsService.parseDateString(self.currentDate)
                let baseID = self.currentID.isEmpty ? "\(resolvedURL)#\(self.items.count)" : self.currentID
                let itemID = self.seenIDs.contains(baseID) ? "\(baseID)#\(self.items.count)" : baseID
                self.seenIDs.insert(itemID)
                let sanitizedCover = AIHotNewsService.sanitizedHTTPURLString(self.currentCover)
                
                self.items.append(AIHotNewsItem(
                    id: itemID,
                    title: title,
                    source: source,
                    urlString: resolvedURL,
                    publishedAt: publishedAt,
                    heatScore: nil,
                    tag: self.currentCategory.isEmpty ? nil : self.currentCategory,
                    coverURLString: sanitizedCover
                ))
            }
        }
        self.popStack()
    }
    
    
    private var isDirectEntryChild: Bool {
        guard self.elementStack.count >= 2 else { return false }
        let parent = self.elementStack[self.elementStack.count - 2]
        return parent == "item" || parent == "entry"
    }
    
    
    private func popStack() {
        if !self.elementStack.isEmpty {
            self.elementStack.removeLast()
        }
        self.elementBuffer = ""
    }
}
