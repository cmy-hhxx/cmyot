//
//  OnlineStickerSearchService.swift
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
import ImageIO

nonisolated enum OnlineStickerSourceID: String, CaseIterable, Codable, Identifiable, Sendable {
    
    case fabiaoqing
    case aigengtu
    case doutula
    case bing
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
            case .fabiaoqing: "发表情"
            case .aigengtu: "梗鲸图库"
            case .doutula: "斗图啦"
            case .bing: "Bing 图库"
        }
    }
}


nonisolated struct OnlineStickerCandidate: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String
    var imageURL: String
    var sourceSite: String
    var category: String
    var tags: [String]
}


/// Multi-source online meme/sticker searcher and quality-filtered importer.
nonisolated enum OnlineStickerSearchService {
    
    // Compiled once (`static let`), zero per-call regex allocation.
    private static let fabiaoqingRegex = try! NSRegularExpression(
        pattern: #"data-original="([^"]+)"[^>]*title="([^"]*)""#,
        options: [.caseInsensitive]
    )
    private static let aigengtuImgRegex = try! NSRegularExpression(
        pattern: #"(?:data-orig|src)="(https?://[^"]+\.(?:png|jpg|jpeg|webp|gif)[^"]*)""#,
        options: [.caseInsensitive]
    )
    private static let doutulaRegex = try! NSRegularExpression(
        pattern: #"data-original="([^"]+)"[^>]*alt="([^"]*)""#,
        options: [.caseInsensitive]
    )
    private static let bingMurlRegex = try! NSRegularExpression(
        pattern: #"murl&quot;:&quot;(https?://[^&]+)&quot;"#,
        options: [.caseInsensitive]
    )
    
    
    @MainActor
    static var isAutoExpansionEnabled: Bool {
        get {
            CotLocalDatabase.shared.bool(
                forKey: CotLocalDatabase.ConfigKey.onlineStickerExpansionEnabled,
                default: true
            )
        }
        set {
            CotLocalDatabase.shared.set(newValue, forKey: CotLocalDatabase.ConfigKey.onlineStickerExpansionEnabled)
        }
    }
    
    
    @MainActor
    static var enabledSources: [OnlineStickerSourceID] {
        get {
            let raw = CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.enabledOnlineStickerSourcesJSON)
            if let data = raw.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([OnlineStickerSourceID].self, from: data),
               !decoded.isEmpty
            {
                return decoded
            }
            return OnlineStickerSourceID.allCases
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8)
            {
                CotLocalDatabase.shared.set(json, forKey: CotLocalDatabase.ConfigKey.enabledOnlineStickerSourcesJSON)
            }
        }
    }
    
    
    static func search(
        query: String,
        sources: [OnlineStickerSourceID] = OnlineStickerSourceID.allCases,
        limitPerSource: Int = 8
    ) async -> [OnlineStickerCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        var all: [OnlineStickerCandidate] = []
        await withTaskGroup(of: [OnlineStickerCandidate].self) { group in
            for source in sources {
                group.addTask {
                    await Self.fetchFromSource(source, query: trimmed, limit: limitPerSource)
                }
            }
            for await chunk in group {
                all.append(contentsOf: chunk)
            }
        }
        
        var seenURLs: Set<String> = []
        return all.filter { seenURLs.insert($0.imageURL).inserted }
    }
    
    
    /// Searches online sources, downloads the highest-confidence valid image, and persists it locally.
    @MainActor
    static func searchAndAutoExpand(
        query: String,
        preferredCategory: String = "reaction"
    ) async -> StickerAsset? {
        guard Self.isAutoExpansionEnabled else { return nil }
        let sources = Self.enabledSources
        let candidates = await Self.search(query: query, sources: sources, limitPerSource: 4)
        for candidate in candidates.prefix(6) {
            if let imported = await Self.downloadAndImport(candidate: candidate, preferredCategory: preferredCategory) {
                return imported
            }
        }
        return nil
    }
    
    
    @MainActor
    static func downloadAndImport(
        candidate: OnlineStickerCandidate,
        preferredCategory: String? = nil
    ) async -> StickerAsset? {
        guard let url = URL(string: candidate.imageURL) else { return nil }
        let fetched: (data: Data, ext: String)? = await Task.detached(priority: .utility) {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  data.count >= 10_000,
                  data.count <= 8_000_000,
                  Self.passesQualityGate(data: data)
            else { return nil }
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased()
            return (data, ext)
        }.value
        
        guard let fetched else { return nil }
        let cat = preferredCategory ?? candidate.category
        return await CotStickerLibraryStore.shared.addImageData(
            fetched.data,
            formatHint: fetched.ext,
            category: cat,
            meaning: candidate.title,
            moods: [],
            tags: candidate.tags,
            sourceSite: candidate.sourceSite,
            sourceURL: candidate.imageURL
        )
    }
    
    
    private static func passesQualityGate(data: Data) -> Bool {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              min(w, h) >= 180,
              max(w, h) <= 3200
        else { return false }
        let aspect = w / max(1, h)
        return aspect >= 0.4 && aspect <= 2.5
    }
    
    
    // MARK: - Per-Site Adapters
    
    private static func fetchFromSource(_ source: OnlineStickerSourceID, query: String, limit: Int) async -> [OnlineStickerCandidate] {
        switch source {
            case .fabiaoqing: await Self.fetchFabiaoqing(query: query, limit: limit)
            case .aigengtu: await Self.fetchAigengtu(query: query, limit: limit)
            case .doutula: await Self.fetchDoutula(query: query, limit: limit)
            case .bing: await Self.fetchBing(query: query, limit: limit)
        }
    }
    
    
    private static func fetchFabiaoqing(query: String, limit: Int) async -> [OnlineStickerCandidate] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://www.fabiaoqing.com/search/search/keyword/\(encoded)/type/bq/page/1.html"),
              let html = await Self.fetchHTML(url: url)
        else { return [] }
        return Self.extractPairs(
            regex: Self.fabiaoqingRegex,
            in: html,
            sourceSite: "fabiaoqing.com",
            category: "reaction",
            query: query,
            limit: limit
        )
    }
    
    
    private static func fetchAigengtu(query: String, limit: Int) async -> [OnlineStickerCandidate] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://aigengtu.com/archive?q=\(encoded)"),
              let html = await Self.fetchHTML(url: url)
        else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = Self.aigengtuImgRegex.matches(in: html, options: [], range: range)
        var out: [OnlineStickerCandidate] = []
        for match in matches where out.count < limit {
            guard match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: html)
            else { continue }
            let imgURL = String(html[r])
            guard imgURL.contains("/meme/") || imgURL.contains("/preview/") else { continue }
            out.append(OnlineStickerCandidate(
                id: "aig-\(imgURL.hashValue)",
                title: query,
                imageURL: imgURL,
                sourceSite: "aigengtu.com",
                category: StickerCategory.normalize(query),
                tags: [query, "梗鲸"]
            ))
        }
        return out
    }
    
    
    private static func fetchDoutula(query: String, limit: Int) async -> [OnlineStickerCandidate] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.doutupk.com/search?keyword=\(encoded)"),
              let html = await Self.fetchHTML(url: url)
        else { return [] }
        return Self.extractPairs(
            regex: Self.doutulaRegex,
            in: html,
            sourceSite: "doutupk.com",
            category: "reaction",
            query: query,
            limit: limit
        )
    }
    
    
    private static func fetchBing(query: String, limit: Int) async -> [OnlineStickerCandidate] {
        let q = "\(query) 表情包"
        guard let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.bing.com/images/search?q=\(encoded)&first=1"),
              let html = await Self.fetchHTML(url: url)
        else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = Self.bingMurlRegex.matches(in: html, options: [], range: range)
        var out: [OnlineStickerCandidate] = []
        for match in matches where out.count < limit {
            guard match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: html)
            else { continue }
            let imgURL = String(html[r])
            out.append(OnlineStickerCandidate(
                id: "bing-\(imgURL.hashValue)",
                title: query,
                imageURL: imgURL,
                sourceSite: "bing.com",
                category: "reaction",
                tags: [query]
            ))
        }
        return out
    }
    
    
    private static func fetchHTML(url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8)
        else { return nil }
        return html
    }
    
    
    private static func extractPairs(
        regex: NSRegularExpression,
        in html: String,
        sourceSite: String,
        category: String,
        query: String,
        limit: Int
    ) -> [OnlineStickerCandidate] {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)
        var out: [OnlineStickerCandidate] = []
        for match in matches where out.count < limit {
            guard match.numberOfRanges > 2,
                  let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html)
            else { continue }
            var imgURL = String(html[urlRange])
            if imgURL.hasPrefix("//") {
                imgURL = "https:\(imgURL)"
            }
            guard imgURL.hasPrefix("http") else { continue }
            let title = String(html[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(OnlineStickerCandidate(
                id: "\(sourceSite)-\(imgURL.hashValue)",
                title: title.isEmpty ? query : title,
                imageURL: imgURL,
                sourceSite: sourceSite,
                category: category,
                tags: [query, title].filter { !$0.isEmpty }
            ))
        }
        return out
    }
}
