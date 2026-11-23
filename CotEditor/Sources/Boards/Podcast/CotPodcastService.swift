//
//  CotPodcastService.swift
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

@preconcurrency import AVFoundation
import Foundation
import Observation

/// @MainActor AVPlayer podcast engine & SQLite persistence service inspired by PodPin.
@MainActor @Observable
final class CotPodcastService {
    
    static let shared = CotPodcastService()
    static let supportedRates: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0]
    
    private(set) var phase: PodcastPlaybackPhase = .idle
    private(set) var currentEpisode: PodcastEpisodeItem?
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Double = 1.0
    private(set) var volume: Double = 1.0
    
    private(set) var searchResults: [PodcastEpisodeItem] = []
    private(set) var savedEpisodes: [StoredPodcastRecord] = []
    private(set) var historyEpisodes: [StoredPodcastRecord] = []
    private(set) var isSearching: Bool = false
    
    private let client: CotPodcastDataClient
    private let database: CotLocalDatabase
    private let memoryStore: CotMemoryStore
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var dbObserver: (any NSObjectProtocol)?
    private var shouldAutoplayWhenReady = false
    private var lastPersistedSecond = -1
    
    
    init(
        client: CotPodcastDataClient = .shared,
        database: CotLocalDatabase = .shared,
        memoryStore: CotMemoryStore = .shared
    ) {
        self.client = client
        self.database = database
        self.memoryStore = memoryStore
        self.reloadFromDatabase()
        
        if database === CotLocalDatabase.shared {
            self.dbObserver = NotificationCenter.default.addObserver(
                forName: CotLocalDatabase.structuredAssetsDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reloadFromDatabase()
                }
            }
        }
    }
    
    
    isolated deinit {
        if let dbObserver {
            NotificationCenter.default.removeObserver(dbObserver)
        }
        self.tearDownPlayer()
    }
    
    
    func reloadFromDatabase() {
        let all = self.database.fetchStoredPodcasts()
        self.savedEpisodes = all.filter(\.isSaved)
        self.historyEpisodes = all.filter { $0.lastPlayedAt != nil }
    }
    
    
    func isSaved(_ id: String) -> Bool {
        self.savedEpisodes.contains { $0.id == id }
    }
    
    
    func toggleSave(_ episode: PodcastEpisodeItem) {
        let currentlySaved = self.isSaved(episode.id)
        let record = episode.toStoredRecord(
            positionSec: (self.currentEpisode?.id == episode.id) ? self.currentTime : 0,
            isSaved: !currentlySaved
        )
        self.database.upsertStoredPodcast(record)
        self.memoryStore.reloadFromDatabase()
        self.reloadFromDatabase()
    }
    
    
    func searchAndRecommend(for queries: [String], autoplayFirst: Bool) async {
        let cleanQueries = queries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleanQueries.isEmpty else { return }
        
        self.isSearching = true
        defer { self.isSearching = false }
        
        var collected: [PodcastEpisodeItem] = []
        var seen = Set<String>()
        for query in cleanQueries.prefix(3) {
            if let items = try? await self.client.searchEpisodes(matching: query, limit: 14) {
                for item in items where seen.insert(item.audioURL).inserted {
                    collected.append(item)
                }
            }
        }
        self.searchResults = collected
        if let first = collected.first, autoplayFirst || self.currentEpisode == nil {
            self.loadAndPlay(episode: first, autoplay: autoplayFirst)
        }
    }
    
    
    func loadAndPlay(episode: PodcastEpisodeItem, autoplay: Bool = true) {
        guard let url = URL(string: episode.audioURL) else {
            self.phase = .failed("无效音频地址")
            return
        }
        self.persistPosition(force: true)
        self.tearDownPlayer()
        
        let existingPos = self.database.fetchStoredPodcasts()
            .first(where: { $0.id == episode.id })?.playbackPositionSec ?? 0
        let keepSaved = self.isSaved(episode.id)
        self.database.upsertStoredPodcast(episode.toStoredRecord(positionSec: existingPos, isSaved: keepSaved))
        self.reloadFromDatabase()
        
        self.currentEpisode = episode
        self.currentTime = existingPos
        self.duration = episode.duration
        self.phase = .loading
        self.lastPersistedSecond = -1
        self.shouldAutoplayWhenReady = autoplay
        
        let asset: AVURLAsset = if episode.headers.isEmpty {
            AVURLAsset(url: url)
        } else {
            AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": episode.headers])
        }
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.volume = Float(self.volume)
        self.player = player
        let episodeID = episode.id
        
        self.statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak player, weak item] observed, _ in
            Task { @MainActor [weak self] in
                guard let self, let player, let item,
                      observed === item,
                      self.player === player,
                      self.currentEpisode?.id == episodeID
                else { return }
                
                switch observed.status {
                    case .readyToPlay:
                        let secs = observed.duration.seconds
                        if secs.isFinite && secs > 0 {
                            self.duration = secs
                        }
                        if existingPos > 1 && existingPos < max(1, self.duration - 2) {
                            self.seek(to: existingPos, autoplayAfterSeek: self.shouldAutoplayWhenReady)
                        } else if self.shouldAutoplayWhenReady {
                            self.play()
                        } else {
                            self.phase = .paused
                        }
                    case .failed:
                        self.phase = .failed(observed.error?.localizedDescription ?? "无法播放")
                    default:
                        break
                }
            }
        }
        
        self.durationObservation = item.observe(\.duration, options: [.new]) { [weak self, weak player, weak item] observed, _ in
            Task { @MainActor [weak self] in
                guard let self, let player, let item,
                      observed === item,
                      self.player === player,
                      self.currentEpisode?.id == episodeID
                else { return }
                let secs = observed.duration.seconds
                if secs.isFinite && secs > 0 {
                    self.duration = secs
                }
            }
        }
        
        self.timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self, weak player] p, _ in
            Task { @MainActor [weak self] in
                guard let self, let player, p === player, self.currentEpisode?.id == episodeID else { return }
                guard self.shouldAutoplayWhenReady else { return }
                switch p.timeControlStatus {
                    case .playing: self.phase = .playing
                    case .waitingToPlayAtSpecifiedRate: self.phase = .buffering
                    case .paused: break
                    @unknown default: break
                }
            }
        }
        
        self.timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak player] time in
            Task { @MainActor [weak self] in
                guard let self, let player, self.player === player, self.currentEpisode?.id == episodeID else { return }
                let secs = time.seconds
                if secs.isFinite && secs >= 0 {
                    self.currentTime = secs
                    let secInt = Int(secs.rounded(.down))
                    if secInt / 5 != self.lastPersistedSecond / 5 {
                        self.lastPersistedSecond = secInt
                        self.persistPosition(force: false)
                    }
                }
            }
        }
        
        self.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak player] _ in
            Task { @MainActor [weak self] in
                guard let self, let player, self.player === player, self.currentEpisode?.id == episodeID else { return }
                self.phase = .finished
                self.shouldAutoplayWhenReady = false
                self.currentTime = self.duration
                self.persistPosition(force: true)
            }
        }
    }
    
    
    func play() {
        guard let player = self.player else { return }
        if self.phase == .finished {
            self.shouldAutoplayWhenReady = true
            self.seek(to: 0, autoplayAfterSeek: true)
            return
        }
        self.shouldAutoplayWhenReady = true
        self.phase = .buffering
        player.playImmediately(atRate: Float(self.rate))
    }
    
    
    func pause() {
        self.shouldAutoplayWhenReady = false
        self.player?.pause()
        if self.phase != .finished {
            self.phase = .paused
        }
        self.persistPosition(force: true)
    }
    
    
    func togglePlayback() {
        if self.phase.hasPlaybackIntent {
            self.pause()
        } else {
            self.play()
        }
    }
    
    
    func skipBackward() {
        self.seek(to: max(0, self.currentTime - 15))
    }
    
    
    func skipForward() {
        let cap = self.duration > 0 ? self.duration : self.currentTime + 30
        self.seek(to: min(cap, self.currentTime + 30))
    }
    
    
    func seek(to target: TimeInterval, autoplayAfterSeek: Bool? = nil) {
        guard let player = self.player else { return }
        let clamped = max(0, self.duration > 0 ? min(target, self.duration) : target)
        let shouldResume = autoplayAfterSeek ?? self.phase.hasPlaybackIntent
        let cmTarget = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cmTarget, toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 0.25, preferredTimescale: 600)) { [weak self, weak player] finished in
            Task { @MainActor [weak self] in
                guard let self, let player, self.player === player, finished else { return }
                self.currentTime = clamped
                self.persistPosition(force: true)
                if shouldResume && self.shouldAutoplayWhenReady {
                    player.playImmediately(atRate: Float(self.rate))
                } else {
                    self.phase = .paused
                }
            }
        }
    }
    
    
    func setRate(_ newRate: Double) {
        self.rate = newRate
        if self.phase.hasPlaybackIntent {
            self.player?.rate = Float(newRate)
        }
    }
    
    
    private func persistPosition(force: Bool) {
        guard let ep = self.currentEpisode else { return }
        if force || self.currentTime > 0 {
            self.database.updatePodcastPlaybackPosition(
                id: ep.id,
                positionSec: self.currentTime,
                durationSec: self.duration
            )
        }
    }
    
    
    private func tearDownPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        self.timeObserver = nil
        self.statusObservation?.invalidate()
        self.statusObservation = nil
        self.durationObservation?.invalidate()
        self.durationObservation = nil
        self.timeControlObservation?.invalidate()
        self.timeControlObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        self.endObserver = nil
        self.player?.pause()
        self.player = nil
        self.shouldAutoplayWhenReady = false
    }
}
