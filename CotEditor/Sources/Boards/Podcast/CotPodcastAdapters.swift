//
//  CotPodcastAdapters.swift
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

/// Resolves podcast episodes from Apple Podcasts Search (`itunes.apple.com/search`)
/// and public Xiaoyuzhou / Bilibili / direct audio URLs (adapted from PodPin).
actor CotPodcastDataClient {
    
    static let shared = CotPodcastDataClient()
    
    private let session: URLSession
    private static let safariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15"
    
    
    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 25
            self.session = URLSession(configuration: config)
        }
    }
    
    
    // MARK: - Search Episodes by Topic / Confusion Query
    
    func searchEpisodes(matching query: String, limit: Int = 20) async throws -> [PodcastEpisodeItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https"
        {
            if let imported = try await self.importEpisode(from: url) {
                return [imported]
            }
        }
        
        async let cnResults = self.queryITunes(term: trimmed, country: "CN", limit: limit)
        async let usResults = self.queryITunes(term: trimmed, country: "US", limit: 8)
        
        let primary = (try? await cnResults) ?? []
        let secondary = primary.count < 6 ? ((try? await usResults) ?? []) : []
        
        var seen = Set<String>()
        var merged: [PodcastEpisodeItem] = []
        for item in primary + secondary {
            if seen.insert(item.audioURL).inserted {
                merged.append(item)
            }
        }
        return merged
    }
    
    
    private func queryITunes(term: String, country: String, limit: Int) async throws -> [PodcastEpisodeItem] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcastEpisode"),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        guard let url = components.url else { return [] }
        
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue(Self.safariUA, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await self.session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        
        let decoded = try JSONDecoder().decode(ITunesPodcastSearchResponse.self, from: data)
        let formatter = ISO8601DateFormatter()
        
        return decoded.results.compactMap { row -> PodcastEpisodeItem? in
            guard let audioURL = row.episodeUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !audioURL.isEmpty,
                  let title = row.trackName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty
            else { return nil }
            
            let trackID = row.trackId.map(String.init) ?? audioURL
            let showName = row.collectionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let artwork = row.artworkUrl600 ?? row.artworkUrl160 ?? ""
            let duration = Double(row.trackTimeMillis ?? 0) / 1000.0
            let summary = (row.shortDescription ?? row.description ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let pubDate = row.releaseDate.flatMap { formatter.date(from: $0) }
            let sourceURL = row.trackViewUrl ?? audioURL
            
            return PodcastEpisodeItem(
                id: "itunes:\(trackID)",
                platform: audioURL.contains("xiaoyuzhou") ? "xiaoyuzhou" : "podcast",
                title: title,
                showName: showName,
                sourceURL: sourceURL,
                audioURL: audioURL,
                headers: [:],
                artworkURL: artwork,
                duration: duration,
                summary: summary,
                topicTag: term,
                publishedAt: pubDate
            )
        }
    }
    
    
    // MARK: - Direct Link Import (Xiaoyuzhou / Bilibili / Direct Audio)
    
    func importEpisode(from url: URL) async throws -> PodcastEpisodeItem? {
        let host = url.host?.lowercased() ?? ""
        if host.contains("xiaoyuzhoufm.com") {
            return try await self.importXiaoyuzhou(url: url)
        }
        if host.contains("bilibili.com") || host.contains("b23.tv") {
            return try await self.importBilibili(url: url)
        }
        let ext = url.pathExtension.lowercased()
        if ["mp3", "m4a", "aac", "wav", "ogg"].contains(ext) {
            return PodcastEpisodeItem(
                id: "url:\(url.absoluteString)",
                platform: "audio",
                title: url.deletingPathExtension().lastPathComponent,
                showName: host,
                sourceURL: url.absoluteString,
                audioURL: url.absoluteString
            )
        }
        return nil
    }
    
    
    private func importXiaoyuzhou(url: URL) async throws -> PodcastEpisodeItem? {
        guard let episodeID = url.path.split(separator: "/").last.map(String.init), !episodeID.isEmpty else {
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 18
        req.setValue(Self.safariUA, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await self.session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8),
              let marker = html.range(of: "<script id=\"__NEXT_DATA__\""),
              let openingEnd = html[marker.upperBound...].firstIndex(of: ">"),
              let closing = html.range(of: "</script>", range: openingEnd..<html.endIndex),
              let jsonData = String(html[html.index(after: openingEnd)..<closing.lowerBound]).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let props = root["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any],
              let episode = pageProps["episode"] as? [String: Any],
              let title = episode["title"] as? String,
              let enclosure = episode["enclosure"] as? [String: Any],
              let audioURL = enclosure["url"] as? String
        else { return nil }
        
        let podcast = episode["podcast"] as? [String: Any] ?? [:]
        let showTitle = (podcast["title"] as? String) ?? "小宇宙"
        let duration = (episode["duration"] as? NSNumber)?.doubleValue ?? 0
        let pic = ((episode["image"] as? [String: Any])?["picUrl"] as? String)
            ?? ((podcast["image"] as? [String: Any])?["picUrl"] as? String)
            ?? ""
        let canonical = "https://www.xiaoyuzhoufm.com/episode/\(episodeID)"
        return PodcastEpisodeItem(
            id: "xyz:\(episodeID)",
            platform: "xiaoyuzhou",
            title: title,
            showName: showTitle,
            sourceURL: canonical,
            audioURL: audioURL,
            headers: ["Referer": canonical],
            artworkURL: pic,
            duration: duration,
            summary: (episode["shownotes"] as? String) ?? ""
        )
    }
    
    
    private func importBilibili(url: URL) async throws -> PodcastEpisodeItem? {
        var resolvedURL = url
        if url.host?.lowercased().hasSuffix("b23.tv") == true {
            var r = URLRequest(url: url)
            r.setValue(Self.safariUA, forHTTPHeaderField: "User-Agent")
            let (_, resp) = try await self.session.data(for: r)
            if let final = resp.url {
                resolvedURL = final
            }
        }
        let segments = resolvedURL.path.split(separator: "/")
        guard segments.count >= 2, segments[0].lowercased() == "video" else { return nil }
        let bvid = String(segments[1])
        
        guard let viewURL = URL(string: "https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)") else {
            return nil
        }
        var viewReq = URLRequest(url: viewURL)
        viewReq.setValue(Self.safariUA, forHTTPHeaderField: "User-Agent")
        viewReq.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        let (viewData, _) = try await self.session.data(for: viewReq)
        guard let viewJSON = try? JSONSerialization.jsonObject(with: viewData) as? [String: Any],
              let videoData = viewJSON["data"] as? [String: Any],
              let title = videoData["title"] as? String,
              let owner = (videoData["owner"] as? [String: Any])?["name"] as? String,
              let pages = videoData["pages"] as? [[String: Any]],
              let firstPage = pages.first,
              let cid = firstPage["cid"] as? Int64
        else { return nil }
        
        guard let playURL = URL(string: "https://api.bilibili.com/x/player/playurl?bvid=\(bvid)&cid=\(cid)&fnval=16&qn=80") else {
            return nil
        }
        var playReq = URLRequest(url: playURL)
        playReq.setValue(Self.safariUA, forHTTPHeaderField: "User-Agent")
        playReq.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        let (playData, _) = try await self.session.data(for: playReq)
        guard let playJSON = try? JSONSerialization.jsonObject(with: playData) as? [String: Any],
              let pData = playJSON["data"] as? [String: Any],
              let dash = pData["dash"] as? [String: Any],
              let audios = dash["audio"] as? [[String: Any]],
              let bestAudio = audios.first(where: { ($0["baseUrl"] as? String) != nil }),
              let streamURL = bestAudio["baseUrl"] as? String
        else { return nil }
        
        let pic = ((videoData["pic"] as? String) ?? "").replacingOccurrences(of: "http://", with: "https://")
        let duration = TimeInterval((firstPage["duration"] as? Int) ?? 0)
        return PodcastEpisodeItem(
            id: "bili:\(bvid)",
            platform: "bilibili",
            title: title,
            showName: owner,
            sourceURL: "https://www.bilibili.com/video/\(bvid)",
            audioURL: streamURL,
            headers: [
                "Referer": "https://www.bilibili.com/",
                "Origin": "https://www.bilibili.com",
                "User-Agent": Self.safariUA,
            ],
            artworkURL: pic,
            duration: duration
        )
    }
}


private struct ITunesPodcastSearchResponse: Decodable {
    let results: [ITunesPodcastEpisodeDTO]
}


private struct ITunesPodcastEpisodeDTO: Decodable {
    let trackId: Int64?
    let trackName: String?
    let collectionName: String?
    let episodeUrl: String?
    let trackViewUrl: String?
    let artworkUrl160: String?
    let artworkUrl600: String?
    let trackTimeMillis: Int?
    let shortDescription: String?
    let description: String?
    let releaseDate: String?
}
