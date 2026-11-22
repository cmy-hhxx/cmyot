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

import Foundation
import Observation

/// A single AI industry news item fetched from `https://aihot.news/agent`.
nonisolated struct AIHotNewsItem: Identifiable, Codable, Hashable, Sendable {
    
    var id: String
    var title: String
    var source: String
    var urlString: String
    var publishedAt: Date?
    var heatScore: Int?
    var tag: String?
    
    var url: URL? {
        guard let sanitized = AIHotNewsService.sanitizedHTTPURLString(self.urlString) else { return nil }
        return URL(string: sanitized)
    }
    
    
    /// Short, pill-free metadata string (e.g. `12m · 96🔥` or `HackerNews`).
    var conciseMetaLabel: String {
        var parts: [String] = []
        if !self.source.isEmpty {
            parts.append(self.source)
        }
        if let score = self.heatScore, score > 0 {
            parts.append("\(score)°")
        } else if let tag = self.tag, !tag.isEmpty {
            parts.append(tag)
        }
        return parts.joined(separator: " · ")
    }
}


/// Live industry news fetcher for the Analytics Dashboard's NEWS column (`https://aihot.news/agent`).
@MainActor @Observable
final class AIHotNewsService {
    
    static let shared = AIHotNewsService()
    nonisolated static let portalURL = URL(string: "https://aihot.news/agent")!
    
    private static let cacheTTL: TimeInterval = 5 * 60
    private static let endpoints: [String] = [
        "https://aihot.news/api/v1/agent/latest",
        "https://aihot.news/api/v1/items?window=24h&limit=12",
        "https://aihot.news/api/v1/agent/hot",
        "https://aihot.news/rss",
    ]
    
    private(set) var items: [AIHotNewsItem] = []
    private(set) var isLoading = false
    private(set) var lastUpdatedAt: Date?
    private(set) var loadFailed = false
    
    
    private init() {
        self.loadCachedItems()
    }
    
    
    /// Refreshes AI industry news from `aihot.news` when stale or forced.
    func refreshIfNeeded(force: Bool = false) async {
        
        guard !self.isLoading else { return }
        if !force,
           let lastUpdatedAt = self.lastUpdatedAt,
           Date().timeIntervalSince(lastUpdatedAt) < Self.cacheTTL,
           !self.items.isEmpty
        {
            return
        }
        
        self.isLoading = true
        defer { self.isLoading = false }
        
        var parsedItems: [AIHotNewsItem] = []
        for endpointString in Self.endpoints {
            guard !Task.isCancelled else { return }
            guard let url = URL(string: endpointString) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(
                "application/json, text/markdown, application/rss+xml, application/xml, text/plain;q=0.9, */*;q=0.8",
                forHTTPHeaderField: "Accept"
            )
            request.setValue("CotEditor/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      !data.isEmpty
                else { continue }
                
                let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                let candidate: [AIHotNewsItem]
                if contentType.contains("xml") || endpointString.hasSuffix("/rss") {
                    candidate = Self.parseRSS(data)
                } else {
                    let fromJSON = Self.parseJSON(data)
                    if !fromJSON.isEmpty {
                        candidate = fromJSON
                    } else if let text = String(data: data, encoding: .utf8) {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("<") {
                            candidate = Self.parseRSS(data)
                        } else {
                            candidate = Self.parseAgentMarkdown(trimmed)
                        }
                    } else {
                        candidate = []
                    }
                }
                
                if !candidate.isEmpty {
                    parsedItems = Array(candidate.prefix(16))
                    break
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                continue
            }
        }
        
        guard !Task.isCancelled else { return }
        if !parsedItems.isEmpty {
            self.items = parsedItems
            self.lastUpdatedAt = Date()
            self.loadFailed = false
            self.saveCachedItems(parsedItems)
        } else {
            self.loadFailed = self.items.isEmpty
        }
    }
    
    
    // MARK: Persistence
    
    private func loadCachedItems() {
        
        let raw = CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.aiHotNewsCacheJSON, default: "")
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return }
        if let decoded = try? JSONDecoder().decode([AIHotNewsItem].self, from: data), !decoded.isEmpty {
            self.items = decoded
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
            
            results.append(AIHotNewsItem(
                id: itemID,
                title: title,
                source: source,
                urlString: resolvedURL,
                publishedAt: publishedAt,
                heatScore: heatScore,
                tag: tag
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
    
    
    fileprivate nonisolated static func hostLabel(from urlString: String) -> String {
        
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else {
            return "aihot.news"
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
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
        } else if self.inEntry,
                  self.isDirectEntryChild,
                  local == "link",
                  let href = attributeDict["href"],
                  !href.isEmpty
        {
            let rel = attributeDict["rel"]?.lowercased()
            if rel == nil || rel == "alternate" || self.currentLink.isEmpty {
                self.currentLink = href
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
                
                self.items.append(AIHotNewsItem(
                    id: itemID,
                    title: title,
                    source: source,
                    urlString: resolvedURL,
                    publishedAt: publishedAt,
                    heatScore: nil,
                    tag: self.currentCategory.isEmpty ? nil : self.currentCategory
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
