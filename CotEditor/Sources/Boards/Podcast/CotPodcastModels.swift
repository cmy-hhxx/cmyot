//
//  CotPodcastModels.swift
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

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// Playback lifecycle state adapted from PodPin's `AudioPlaybackController`.
nonisolated enum PodcastPlaybackPhase: Equatable, Sendable {
    
    case idle
    case loading
    case buffering
    case paused
    case playing
    case finished
    case failed(String)
    
    var isPlaying: Bool { self == .playing }
    var hasPlaybackIntent: Bool {
        switch self {
            case .playing, .buffering: true
            case .idle, .loading, .paused, .finished, .failed: false
        }
    }
}


/// Unified podcast episode model across Apple Podcasts Search, Xiaoyuzhou, Bilibili, and SQLite.
nonisolated struct PodcastEpisodeItem: Identifiable, Codable, Hashable, Sendable {
    
    let id: String
    let platform: String
    let title: String
    let showName: String
    let sourceURL: String
    let audioURL: String
    var headers: [String: String]
    let artworkURL: String
    let duration: TimeInterval
    let summary: String
    let topicTag: String
    let publishedAt: Date?
    
    
    init(
        id: String,
        platform: String,
        title: String,
        showName: String,
        sourceURL: String,
        audioURL: String,
        headers: [String: String] = [:],
        artworkURL: String = "",
        duration: TimeInterval = 0,
        summary: String = "",
        topicTag: String = "",
        publishedAt: Date? = nil
    ) {
        self.id = id
        self.platform = platform
        self.title = title
        self.showName = showName
        self.sourceURL = sourceURL
        self.audioURL = audioURL
        self.headers = headers
        self.artworkURL = artworkURL
        self.duration = duration
        self.summary = summary
        self.topicTag = topicTag
        self.publishedAt = publishedAt
    }
    
    
    init(record: StoredPodcastRecord) {
        self.init(
            id: record.id,
            platform: record.platform,
            title: record.title,
            showName: record.showName,
            sourceURL: record.sourceURL,
            audioURL: record.audioURL,
            headers: record.platform == "bilibili"
                ? ["Referer": "https://www.bilibili.com/", "Origin": "https://www.bilibili.com"]
                : (record.platform == "xiaoyuzhou" ? ["Referer": record.sourceURL] : [:]),
            artworkURL: record.artworkURL,
            duration: record.durationSec,
            summary: record.notes,
            topicTag: record.topicTag,
            publishedAt: record.lastPlayedAt
        )
    }
    
    
    func toStoredRecord(positionSec: Double = 0, isSaved: Bool = false) -> StoredPodcastRecord {
        let now = Date()
        return StoredPodcastRecord(
            id: self.id,
            itemKind: "episode",
            platform: self.platform,
            title: self.title,
            showName: self.showName,
            sourceURL: self.sourceURL,
            audioURL: self.audioURL,
            artworkURL: self.artworkURL,
            durationSec: self.duration,
            playbackPositionSec: positionSec,
            isSaved: isSaved,
            topicTag: self.topicTag,
            notes: self.summary,
            lastPlayedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }
}


/// Pure time formatter matching PodPin (`1:23:45` / `12:34` / `−04:12`).
nonisolated enum PodcastTimeFormatter {
    
    static func string(for time: TimeInterval?) -> String {
        guard let time, time.isFinite, time >= 0 else { return "—" }
        let seconds = max(0, Int(time.rounded(.down)))
        let hours = seconds / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    
    
    static func remainingString(current: TimeInterval?, duration: TimeInterval?) -> String {
        guard let current, current.isFinite,
              let duration, duration.isFinite, duration > 0
        else { return "—" }
        return "−\(Self.string(for: max(duration - max(current, 0), 0)))"
    }
}


/// Ambient artwork chroma extractor ported from PodPin's `ArtworkColorExtractor`.
@MainActor @Observable
final class PodcastArtworkColorModel {
    
    private(set) var color: Color?
    private var task: Task<Void, Never>?
    private static var cache: [String: Color] = [:]
    private static var cacheOrder: [String] = []
    private static let maxCachedColors = 64
    
    
    func load(from urlString: String?) {
        self.task?.cancel()
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else {
            self.color = nil
            return
        }
        if let cached = Self.cache[urlString] {
            self.color = cached
            return
        }
        self.task = Task { [weak self] in
            let sampled = await Task.detached(priority: .utility) { () -> (Double, Double, Double)? in
                guard let (data, response) = try? await URLSession.shared.data(from: url),
                      (response as? HTTPURLResponse)?.statusCode == 200
                else { return nil }
                return Self.extractRGB(from: data)
            }.value
            guard !Task.isCancelled, let sampled else { return }
            let lum = sampled.0 * 0.2126 + sampled.1 * 0.7152 + sampled.2 * 0.0722
            let sat = 0.55
            let r = min((lum + (sampled.0 - lum) * sat) * 0.62 + 0.04, 1)
            let g = min((lum + (sampled.1 - lum) * sat) * 0.62 + 0.04, 1)
            let b = min((lum + (sampled.2 - lum) * sat) * 0.62 + 0.04, 1)
            let resolved = Color(red: r, green: g, blue: b)
            Self.cache[urlString] = resolved
            Self.cacheOrder.removeAll { $0 == urlString }
            Self.cacheOrder.append(urlString)
            while Self.cacheOrder.count > Self.maxCachedColors {
                let evicted = Self.cacheOrder.removeFirst()
                Self.cache.removeValue(forKey: evicted)
            }
            self?.color = resolved
        }
    }
    
    
    nonisolated private static func extractRGB(from data: Data) -> (Double, Double, Double)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 48,
                ] as CFDictionary
              )
        else { return nil }
        
        let side = 24
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * side)
        guard let ctx = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        
        var wr = 0.0
        var wg = 0.0
        var wb = 0.0
        var tw = 0.0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255.0
            guard alpha > 0.2 else { continue }
            let r = min(Double(pixels[offset]) / 255.0 / alpha, 1)
            let g = min(Double(pixels[offset + 1]) / 255.0 / alpha, 1)
            let b = min(Double(pixels[offset + 2]) / 255.0 / alpha, 1)
            let hi = max(r, g, b)
            let lo = min(r, g, b)
            let chroma = hi - lo
            let sat = hi > 0 ? chroma / hi : 0
            let lum = r * 0.2126 + g * 0.7152 + b * 0.0722
            guard lum > 0.08, lum < 0.92, sat > 0.12 else { continue }
            let w = alpha * sat * sat * (0.5 + chroma)
            wr += r * w
            wg += g * w
            wb += b * w
            tw += w
        }
        guard tw > 0 else { return nil }
        return (wr / tw, wg / tw, wb / tw)
    }
}
