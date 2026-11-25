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
import CryptoKit
import Foundation
import Observation
import UserNotifications

/// @MainActor AVPlayer podcast engine, offline downloader, Agent Bot curator, and SQLite persistence service.
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
    private(set) var downloadStates: [String: PodcastDownloadState] = [:]
    private(set) var downloadedPaths: [String: String] = [:]
    private(set) var agentReminders: [AgentPodcastRecommendation] = []
    private(set) var sleepTimerRemainingSec: Int? = nil
    
    private let client: CotPodcastDataClient
    private let database: CotLocalDatabase
    private let memoryStore: CotMemoryStore
    private let downloadsDirectory: URL
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var dbObserver: (any NSObjectProtocol)?
    private var sleepTimerTask: Task<Void, Never>?
    private var shouldAutoplayWhenReady = false
    private var lastPersistedSecond = -1
    
    
    init(
        client: CotPodcastDataClient = .shared,
        database: CotLocalDatabase = .shared,
        memoryStore: CotMemoryStore = .shared,
        downloadsDirectory: URL? = nil
    ) {
        self.client = client
        self.database = database
        self.memoryStore = memoryStore
        if let downloadsDirectory {
            self.downloadsDirectory = downloadsDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            self.downloadsDirectory = appSupport
                .appending(path: "CotEditor", directoryHint: .isDirectory)
                .appending(path: "Podcasts", directoryHint: .isDirectory)
                .appending(path: "Downloads", directoryHint: .isDirectory)
        }
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
        self.sleepTimerTask?.cancel()
        if let dbObserver {
            NotificationCenter.default.removeObserver(dbObserver)
        }
        self.tearDownPlayer()
    }
    
    
    func reloadFromDatabase() {
        let all = self.database.fetchStoredPodcasts()
        self.savedEpisodes = all.filter(\.isSaved)
        self.historyEpisodes = all.filter { $0.lastPlayedAt != nil }
        self.refreshLocalFileIndex(from: all)
        self.reloadAgentReminders()
    }
    
    
    var downloadedEpisodes: [PodcastEpisodeItem] {
        var seen = Set<String>()
        var list: [PodcastEpisodeItem] = []
        for record in self.savedEpisodes + self.historyEpisodes {
            guard seen.insert(record.id).inserted else { continue }
            let item = PodcastEpisodeItem(record: record)
            if self.isDownloaded(item) {
                list.append(item)
            }
        }
        return list
    }
    
    
    var unreadReminders: [AgentPodcastRecommendation] {
        self.agentReminders.filter { !$0.isRead }
    }
    
    
    func isSaved(_ id: String) -> Bool {
        self.savedEpisodes.contains { $0.id == id }
    }
    
    
    func isDownloaded(_ episode: PodcastEpisodeItem) -> Bool {
        self.localAudioURL(for: episode) != nil
    }
    
    
    func localAudioURL(for episode: PodcastEpisodeItem) -> URL? {
        if let path = self.downloadedPaths[episode.id], FileManager.default.fileExists(atPath: path) {
            return URL(filePath: path)
        }
        for candidate in Self.candidateLocalURLs(for: episode, in: self.downloadsDirectory) {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
    
    
    func toggleSave(_ episode: PodcastEpisodeItem) {
        let currentlySaved = self.isSaved(episode.id)
        let record = episode.toStoredRecord(
            positionSec: (self.currentEpisode?.id == episode.id) ? self.currentTime : 0,
            isSaved: !currentlySaved
        )
        self.database.upsertStoredPodcast(record)
        self.memoryStore.reloadPodcasts()
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
    
    
    /// Offline-caches `episode` audio into `downloadsDirectory`, marks it saved in SQLite, and returns the local file URL.
    @discardableResult
    func downloadEpisode(_ episode: PodcastEpisodeItem) async -> URL? {
        if let existing = self.localAudioURL(for: episode) {
            self.downloadedPaths[episode.id] = existing.path
            self.downloadStates[episode.id] = .downloaded(existing.path)
            return existing
        }
        guard let remoteURL = URL(string: episode.audioURL) else {
            self.downloadStates[episode.id] = .failed("无效音频地址")
            return nil
        }
        
        self.downloadStates[episode.id] = .downloading(0.15)
        var req = URLRequest(url: remoteURL)
        req.timeoutInterval = 120
        for (k, v) in episode.headers {
            req.setValue(v, forHTTPHeaderField: k)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  !data.isEmpty
            else {
                self.downloadStates[episode.id] = .failed("下载响应异常")
                return nil
            }
            try FileManager.default.createDirectory(at: self.downloadsDirectory, withIntermediateDirectories: true)
            let destURL = Self.preferredLocalURL(for: episode, in: self.downloadsDirectory)
            try data.write(to: destURL, options: .atomic)
            
            self.downloadedPaths[episode.id] = destURL.path
            self.downloadStates[episode.id] = .downloaded(destURL.path)
            
            let existingPos = self.historyEpisodes.first(where: { $0.id == episode.id })?.playbackPositionSec
                ?? self.savedEpisodes.first(where: { $0.id == episode.id })?.playbackPositionSec
                ?? 0
            self.database.upsertStoredPodcast(episode.toStoredRecord(positionSec: existingPos, isSaved: true))
            self.memoryStore.reloadPodcasts()
            self.reloadFromDatabase()
            return destURL
        } catch {
            self.downloadStates[episode.id] = .failed(error.localizedDescription)
            return nil
        }
    }
    
    
    /// Autonomously searches for a podcast matching `topic`, caches it offline if possible,
    /// saves it to the library, records a listen reminder, and notifies Butler & macOS Notification Center.
    @discardableResult
    func agentDiscoverDownloadAndRemind(
        topic: String,
        reason: String? = nil,
        openBoard: Bool = false
    ) async -> PodcastEpisodeItem? {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let workerID = "podcast-\(UUID().uuidString.prefix(8))"
        CotButlerProactiveEngine.shared.startWorker(
            id: workerID,
            title: AppLanguage.text("正在为你搜寻「\(trimmed)」播客", en: "Finding podcast for \(trimmed)"),
            detail: AppLanguage.text("检索单集并离线下载音频", en: "Searching and caching offline audio"),
            actionBoard: "podcast",
            actionQuery: trimmed
        )
        
        var results = (try? await self.client.searchEpisodes(matching: trimmed, limit: 12)) ?? []
        if results.isEmpty {
            let shortTokens = trimmed.split(separator: " ").map(String.init)
            if let firstToken = shortTokens.first, firstToken != trimmed {
                results = (try? await self.client.searchEpisodes(matching: firstToken, limit: 10)) ?? []
            }
        }
        
        guard let picked = results.first(where: { $0.duration >= 180 }) ?? results.first else {
            CotButlerProactiveEngine.shared.finishWorker(
                id: workerID,
                title: AppLanguage.text("暂未找到「\(trimmed)」匹配播客", en: "No podcast match for \(trimmed)"),
                isError: true
            )
            return nil
        }
        
        // Save into library first, then download audio offline
        self.database.upsertStoredPodcast(picked.toStoredRecord(positionSec: 0, isSaved: true))
        self.memoryStore.reloadPodcasts()
        let localURL = await self.downloadEpisode(picked)
        self.searchResults = results
        
        let resolvedReason = (reason?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? AppLanguage.text("围绕「\(trimmed)」为你精选的深度节目，点击即可沉浸收听。", en: "Curated for \(trimmed). Ready to listen.")
        self.recordAgentRecommendation(picked, topic: trimmed, reason: resolvedReason, localPath: localURL?.path)
        
        CotButlerProactiveEngine.shared.finishWorker(
            id: workerID,
            title: AppLanguage.text("播客已就绪：《\(picked.title)》", en: "Ready: \(picked.title)"),
            detail: localURL != nil
                ? AppLanguage.text("已离线缓存，点击前往播客看板收听", en: "Downloaded offline · Click to listen")
                : AppLanguage.text("已加入待听列表，点击前往收听", en: "Queued in Podcast board"),
            isError: false,
            actionBoard: "podcast",
            actionQuery: trimmed
        )
        
        self.postLocalListenNotification(episodeTitle: picked.title, topic: trimmed)
        if openBoard {
            NotificationCenter.default.post(name: CotButlerManager.openHubRequestedNotification, object: self)
        }
        return picked
    }
    
    
    func recordAgentRecommendation(
        _ episode: PodcastEpisodeItem,
        topic: String,
        reason: String,
        localPath: String?
    ) {
        let rec = AgentPodcastRecommendation(
            id: "rec-\(UUID().uuidString.prefix(10).lowercased())",
            episodeID: episode.id,
            topic: topic,
            reason: reason,
            episodeTitle: episode.title,
            showName: episode.showName,
            artworkURL: episode.artworkURL,
            localFilePath: localPath,
            createdAt: Date(),
            isRead: false
        )
        self.agentReminders.removeAll { $0.episodeID == episode.id }
        self.agentReminders.insert(rec, at: 0)
        if self.agentReminders.count > 12 {
            self.agentReminders = Array(self.agentReminders.prefix(12))
        }
        self.persistAgentReminders()
    }
    
    
    func markReminderRead(id: String) {
        guard let idx = self.agentReminders.firstIndex(where: { $0.id == id }) else { return }
        self.agentReminders[idx].isRead = true
        self.persistAgentReminders()
    }
    
    
    func dismissReminder(id: String) {
        self.agentReminders.removeAll { $0.id == id }
        self.persistAgentReminders()
    }
    
    
    func setSleepTimer(minutes: Int?) {
        self.sleepTimerTask?.cancel()
        self.sleepTimerTask = nil
        guard let minutes, minutes > 0 else {
            self.sleepTimerRemainingSec = nil
            return
        }
        self.sleepTimerRemainingSec = minutes * 60
        self.sleepTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, let rem = self.sleepTimerRemainingSec else { break }
                if rem <= 1 {
                    self.sleepTimerRemainingSec = nil
                    self.pause()
                    break
                } else {
                    self.sleepTimerRemainingSec = rem - 1
                }
            }
        }
    }
    
    
    func loadAndPlay(episode: PodcastEpisodeItem, autoplay: Bool = true) {
        let localURL = self.localAudioURL(for: episode)
        guard let playbackURL = localURL ?? URL(string: episode.audioURL) else {
            self.phase = .failed("无效音频地址")
            return
        }
        self.persistPosition(force: true)
        self.tearDownPlayer()
        
        let existingPos = self.historyEpisodes.first(where: { $0.id == episode.id })?.playbackPositionSec
            ?? self.savedEpisodes.first(where: { $0.id == episode.id })?.playbackPositionSec
            ?? 0
        let keepSaved = self.isSaved(episode.id)
        self.database.upsertStoredPodcast(episode.toStoredRecord(positionSec: existingPos, isSaved: keepSaved))
        self.reloadFromDatabase()
        
        self.currentEpisode = episode
        self.currentTime = existingPos
        self.duration = episode.duration
        self.phase = .loading
        self.lastPersistedSecond = -1
        self.shouldAutoplayWhenReady = autoplay
        
        let asset: AVURLAsset = if localURL != nil || episode.headers.isEmpty {
            AVURLAsset(url: playbackURL)
        } else {
            AVURLAsset(url: playbackURL, options: ["AVURLAssetHTTPHeaderFieldsKey": episode.headers])
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
            MainActor.assumeIsolated {
                guard let self, let player, self.player === player, self.currentEpisode?.id == episodeID else { return }
                let secs = time.seconds
                if secs.isFinite && secs >= 0 {
                    if abs(secs - self.currentTime) >= 0.25 || secs == 0 {
                        self.currentTime = secs
                    }
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
    
    
    func setVolume(_ newVolume: Double) {
        let clamped = max(0.0, min(1.0, newVolume))
        self.volume = clamped
        self.player?.volume = Float(clamped)
    }
    
    
    // MARK: - Private Helpers
    
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
    
    
    private func refreshLocalFileIndex(from records: [StoredPodcastRecord]) {
        var nextPaths: [String: String] = [:]
        for record in records {
            let item = PodcastEpisodeItem(record: record)
            for candidate in Self.candidateLocalURLs(for: item, in: self.downloadsDirectory) {
                if FileManager.default.fileExists(atPath: candidate.path) {
                    nextPaths[item.id] = candidate.path
                    self.downloadStates[item.id] = .downloaded(candidate.path)
                    break
                }
            }
        }
        self.downloadedPaths = nextPaths
    }
    
    
    private func reloadAgentReminders() {
        let raw = self.database.string(forKey: CotLocalDatabase.ConfigKey.podcastAgentRemindersJSON)
        if let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([AgentPodcastRecommendation].self, from: data)
        {
            self.agentReminders = decoded
        } else {
            self.agentReminders = []
        }
    }
    
    
    private func persistAgentReminders() {
        guard let data = try? JSONEncoder().encode(self.agentReminders),
              let json = String(data: data, encoding: .utf8)
        else { return }
        self.database.set(json, forKey: CotLocalDatabase.ConfigKey.podcastAgentRemindersJSON)
    }
    
    
    private func postLocalListenNotification(episodeTitle: String, topic: String) {
        guard self.database === CotLocalDatabase.shared, !CotLocalDatabase.isRunningUnitTests else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let sendBlock = {
                let content = UNMutableNotificationContent()
                content.title = AppLanguage.text("播客已下载就绪", en: "Podcast Ready to Listen")
                content.body = "\(episodeTitle)（\(topic)）"
                content.sound = .default
                let request = UNNotificationRequest(
                    identifier: "cot.podcast.\(UUID().uuidString)",
                    content: content,
                    trigger: nil
                )
                center.add(request)
            }
            if settings.authorizationStatus == .authorized {
                sendBlock()
            } else if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { sendBlock() }
                }
            }
        }
    }
    
    
    nonisolated static func preferredLocalURL(for episode: PodcastEpisodeItem, in directory: URL) -> URL {
        let hash = SHA256.hash(data: Data(episode.id.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let ext = Self.fileExtension(for: episode.audioURL)
        return directory.appending(path: "ep_\(hash).\(ext)")
    }
    
    
    private nonisolated static func candidateLocalURLs(for episode: PodcastEpisodeItem, in directory: URL) -> [URL] {
        let hash = SHA256.hash(data: Data(episode.id.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let exts = ["m4a", "mp3", "aac", "wav", "ogg"]
        return exts.map { directory.appending(path: "ep_\(hash).\($0)") }
    }
    
    
    private nonisolated static func fileExtension(for audioURLString: String) -> String {
        let pathExt = URL(string: audioURLString)?.pathExtension.lowercased() ?? ""
        if ["m4a", "mp3", "aac", "wav", "ogg"].contains(pathExt) {
            return pathExt
        }
        return "m4a"
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
