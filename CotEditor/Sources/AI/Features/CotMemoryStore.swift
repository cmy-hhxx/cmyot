//
//  CotMemoryStore.swift
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

/// Central @MainActor store exposing the user's structured SQLite KYC memories,
/// audit journal, watched stocks, saved podcasts, followed feeds, and X creators.
@MainActor @Observable
final class CotMemoryStore {
    
    static let shared = CotMemoryStore()
    
    private(set) var memories: [UserKYCMemoryRecord] = []
    private(set) var journal: [UserMemoryJournalEntry] = []
    private(set) var stocks: [WatchlistStockRecord] = []
    private(set) var podcasts: [StoredPodcastRecord] = []
    private(set) var feeds: [FollowedFeedRecord] = []
    private(set) var creators: [FollowedCreatorRecord] = []
    private(set) var revision: Int = 0
    
    private let database: CotLocalDatabase
    private var dbObserver: (any NSObjectProtocol)?
    
    
    init(database: CotLocalDatabase = .shared) {
        self.database = database
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
    }
    
    
    func reloadFromDatabase() {
        self.memories = self.database.fetchKYCMemories()
        self.journal = self.database.fetchMemoryJournal(limit: 40)
        self.stocks = self.database.fetchWatchlistStocks()
        self.podcasts = self.database.fetchStoredPodcasts()
        self.feeds = self.database.fetchFollowedFeeds()
        self.creators = self.database.fetchFollowedCreators()
        self.revision &+= 1
    }
    
    
    func reloadMemoriesAndJournal() {
        self.memories = self.database.fetchKYCMemories()
        self.journal = self.database.fetchMemoryJournal(limit: 40)
        self.revision &+= 1
    }
    
    
    func reloadStocks() {
        self.stocks = self.database.fetchWatchlistStocks()
        self.revision &+= 1
    }
    
    
    func reloadPodcasts() {
        self.podcasts = self.database.fetchStoredPodcasts()
        self.revision &+= 1
    }
    
    
    func reloadFeeds() {
        self.feeds = self.database.fetchFollowedFeeds()
        self.revision &+= 1
    }
    
    
    func reloadCreators() {
        self.creators = self.database.fetchFollowedCreators()
        self.revision &+= 1
    }
    
    
    // MARK: - KYC Memory Operations
    
    func upsertMemory(
        dimension: KYCDimension,
        factKey: String,
        title: String,
        detail: String = "",
        confidence: Double = 0.9,
        source: String = "user_explicit",
        evidenceRef: String? = nil,
        isPinned: Bool? = nil,
        actorBot: String = "Butler"
    ) {
        self.database.upsertKYCMemory(
            dimension: dimension,
            factKey: factKey,
            title: title,
            detail: detail,
            confidence: confidence,
            source: source,
            evidenceRef: evidenceRef,
            isPinned: isPinned,
            actorBot: actorBot
        )
        self.reloadMemoriesAndJournal()
        if self.database === CotLocalDatabase.shared {
            PiKernelManager.shared.scheduleWorkspaceSync()
        }
    }
    
    
    func togglePinned(id: String, isPinned: Bool) {
        self.database.toggleKYCMemoryPinned(id: id, isPinned: isPinned)
        self.reloadMemoriesAndJournal()
    }
    
    
    func deleteMemory(idOrKey: String) {
        self.database.deleteKYCMemory(idOrKey: idOrKey)
        self.reloadMemoriesAndJournal()
        if self.database === CotLocalDatabase.shared {
            PiKernelManager.shared.scheduleWorkspaceSync()
        }
    }
    
    
    /// Synchronizes the 6-hour `UserPersonalityAnalyzer` snapshot into structured KYC records.
    func syncPersonalityProfile(_ profile: UserPersonalityProfile) {
        self.database.withTransaction {
            for tag in profile.tags.prefix(5) {
                self.database.upsertKYCMemory(
                    dimension: .writingStyle,
                    factKey: "persona_tag_\(tag.label)",
                    title: tag.label,
                    detail: tag.explanation,
                    confidence: 0.78,
                    source: "persona_bot",
                    evidenceRef: profile.modelUsed,
                    isPinned: nil,
                    actorBot: "PersonaBot"
                )
            }
            if !profile.conceptTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.database.upsertKYCMemory(
                    dimension: .cognition,
                    factKey: "persona_concept_summary",
                    title: profile.conceptTitle,
                    detail: profile.conceptSummary,
                    confidence: 0.82,
                    source: "persona_bot",
                    evidenceRef: profile.modelUsed,
                    isPinned: nil,
                    actorBot: "PersonaBot"
                )
            }
            for (idx, note) in profile.writingStyleNotes.prefix(3).enumerated() {
                self.database.upsertKYCMemory(
                    dimension: .writingStyle,
                    factKey: "style_note_\(idx)",
                    title: String(note.prefix(24)),
                    detail: note,
                    confidence: 0.76,
                    source: "persona_bot",
                    evidenceRef: nil,
                    isPinned: nil,
                    actorBot: "PersonaBot"
                )
            }
        }
        self.reloadMemoriesAndJournal()
    }
    
    
    // MARK: - Portable Interest Collections
    
    func addOrUpdateStock(_ stock: WatchlistStockRecord) {
        self.database.upsertWatchlistStock(stock)
        self.reloadStocks()
    }
    
    
    func removeStock(instrumentIDOrSymbol: String) {
        self.database.deleteWatchlistStock(instrumentIDOrSymbol: instrumentIDOrSymbol)
        self.reloadStocks()
    }
    
    
    func addOrUpdateFeed(
        title: String,
        siteURL: String,
        feedURL: String = "",
        category: String = "",
        author: String = "",
        notes: String = "",
        addedBy: String = "user"
    ) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSite = Self.normalizedURLString(siteURL)
        guard !cleanTitle.isEmpty || !cleanSite.isEmpty else { return }
        let id = "feed:\((cleanSite.isEmpty ? cleanTitle : cleanSite).lowercased())"
        let record = FollowedFeedRecord(
            id: id,
            title: cleanTitle.isEmpty ? cleanSite : cleanTitle,
            siteURL: cleanSite,
            feedURL: feedURL.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
            author: author.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            isPinned: false,
            addedBy: addedBy,
            createdAt: Date(),
            updatedAt: Date()
        )
        self.database.upsertFollowedFeed(record)
        self.reloadFeeds()
    }
    
    
    func removeFeed(id: String) {
        self.database.deleteFollowedFeed(id: id)
        self.reloadFeeds()
    }
    
    
    func addOrUpdateCreator(
        platform: String = "x",
        handle: String,
        displayName: String = "",
        focusTags: String = "",
        whyFollowing: String = "",
        addedBy: String = "user"
    ) {
        let rawHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHandle = rawHandle.hasPrefix("@") ? rawHandle : "@\(rawHandle)"
        guard cleanHandle.count > 1 else { return }
        let slug = String(cleanHandle.dropFirst()).lowercased()
        let profileURL = platform.lowercased() == "x" ? "https://x.com/\(slug)" : ""
        let id = "\(platform.lowercased()):\(slug)"
        let record = FollowedCreatorRecord(
            id: id,
            platform: platform.lowercased(),
            handle: cleanHandle,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cleanHandle : displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            profileURL: profileURL,
            avatarURL: "",
            focusTags: focusTags.trimmingCharacters(in: .whitespacesAndNewlines),
            whyFollowing: whyFollowing.trimmingCharacters(in: .whitespacesAndNewlines),
            isPinned: false,
            addedBy: addedBy,
            createdAt: Date(),
            updatedAt: Date()
        )
        self.database.upsertFollowedCreator(record)
        self.reloadCreators()
    }
    
    
    func removeCreator(id: String) {
        self.database.deleteFollowedCreator(id: id)
        self.reloadCreators()
    }
    
    
    func removePodcast(id: String) {
        self.database.deleteStoredPodcast(id: id)
        self.reloadPodcasts()
    }
    
    
    // MARK: - Compiled Prompt Context
    
    /// Renders a compact, structured user KYC & asset summary injected into Pi Bot prompts and `SYSTEM.md`.
    func compiledKYCContext(maxMemories: Int = 16) -> String {
        let activeMemories = Array(self.memories.prefix(maxMemories))
        var sections: [String] = []
        
        if !activeMemories.isEmpty {
            var lines: [String] = ["## 用户的习惯与偏好"]
            for dim in KYCDimension.allCases {
                let dimMemories = activeMemories.filter { $0.dimension == dim }
                guard !dimMemories.isEmpty else { continue }
                let joined = dimMemories.map { mem -> String in
                    mem.detail.isEmpty ? mem.title : "\(mem.title)（\(mem.detail)）"
                }.joined(separator: "；")
                lines.append("- [\(dim.label)] \(joined)")
            }
            sections.append(lines.joined(separator: "\n"))
        }
        
        var assetLines: [String] = []
        if !self.stocks.isEmpty {
            let names = self.stocks.prefix(8).map { "\($0.name)(\($0.symbol))" }.joined(separator: "、")
            assetLines.append("- 自选股票：\(names)")
        }
        if !self.feeds.isEmpty {
            let names = self.feeds.prefix(6).map(\.title).joined(separator: "、")
            assetLines.append("- 关注博客/信源：\(names)")
        }
        if !self.creators.isEmpty {
            let names = self.creators.prefix(8).map { $0.displayName == $0.handle ? $0.handle : "\($0.displayName)(\($0.handle))" }.joined(separator: "、")
            assetLines.append("- X 关注：\(names)")
        }
        if !self.podcasts.isEmpty {
            let saved = self.podcasts.filter(\.isSaved).prefix(4).map(\.title).joined(separator: "、")
            if !saved.isEmpty {
                assetLines.append("- 收藏播客：\(saved)")
            }
        }
        if !assetLines.isEmpty {
            sections.append("## 用户的关注内容\n" + assetLines.joined(separator: "\n"))
        }
        
        return sections.joined(separator: "\n\n")
    }
    
    
    private static func normalizedURLString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }
}
