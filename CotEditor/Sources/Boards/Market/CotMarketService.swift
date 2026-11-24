//
//  CotMarketService.swift
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

/// @MainActor market state coordinator backed by SQLite `user_watchlist_stocks` and `CotMarketDataClient`.
@MainActor @Observable
final class CotMarketService {
    
    static let shared = CotMarketService()
    
    private(set) var watchlist: [WatchlistStockRecord] = []
    private(set) var quotes: [String: MarketQuoteSnapshot] = [:]
    private(set) var loadingInstrumentIDs: Set<String> = []
    private(set) var searchResults: [MarketInstrument] = []
    private(set) var isSearching: Bool = false
    var selectedInstrumentName: String?
    
    private let client: CotMarketDataClient
    private let database: CotLocalDatabase
    private let memoryStore: CotMemoryStore
    private var dbObserver: (any NSObjectProtocol)?
    
    
    init(
        client: CotMarketDataClient = .shared,
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
    }
    
    
    func reloadFromDatabase() {
        self.watchlist = self.database.fetchWatchlistStocks()
    }
    
    
    func isWatched(_ instrumentID: String) -> Bool {
        self.watchlist.contains { $0.instrumentID == instrumentID }
    }
    
    
    func toggleWatch(_ instrument: MarketInstrument, thesis: String = "") {
        if self.isWatched(instrument.instrumentID) {
            self.memoryStore.removeStock(instrumentIDOrSymbol: instrument.instrumentID)
        } else {
            let nextOrder = (self.watchlist.map(\.sortOrder).max() ?? -1) + 1
            var record = instrument.toRecord(sortOrder: nextOrder, thesisNote: thesis, addedBy: "user")
            if let q = self.quotes[instrument.instrumentID] {
                record.lastPrice = q.lastPrice
                record.lastChangePct = q.changePercent
            }
            self.memoryStore.addOrUpdateStock(record)
        }
        self.reloadFromDatabase()
    }
    
    
    func resolveAndWatch(
        query: String,
        thesis: String = "",
        addedBy: String = "user",
        database: CotLocalDatabase? = nil,
        memoryStore: CotMemoryStore? = nil
    ) async -> WatchlistStockRecord? {
        let targetDB = database ?? self.database
        let targetStore = memoryStore ?? self.memoryStore
        
        guard let instrument = await self.resolveInstrument(for: query) else { return nil }
        let existing = targetDB.fetchWatchlistStocks()
        let nextOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        var record = instrument.toRecord(sortOrder: nextOrder, thesisNote: thesis, addedBy: addedBy)
        if let q = self.quotes[instrument.instrumentID] {
            record.lastPrice = q.lastPrice
            record.lastChangePct = q.changePercent
        }
        targetStore.addOrUpdateStock(record)
        if targetDB === self.database {
            self.reloadFromDatabase()
        }
        return record
    }
    
    
    func resolveInstrument(for query: String) async -> MarketInstrument? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let alias = MarketAliasCatalog.resolve(trimmed) {
            return alias
        }
        if let existing = self.watchlist.first(where: {
            $0.instrumentID.caseInsensitiveCompare(trimmed) == .orderedSame
                || $0.symbol.caseInsensitiveCompare(trimmed) == .orderedSame
                || $0.name.localizedCaseInsensitiveContains(trimmed)
        }) {
            return MarketInstrument(record: existing)
        }
        if let found = try? await self.client.searchInstruments(matching: trimmed),
           let first = found.first
        {
            return first
        }
        return nil
    }
    
    
    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.searchResults = []
            self.isSearching = false
            return
        }
        self.isSearching = true
        defer { self.isSearching = false }
        self.searchResults = (try? await self.client.searchInstruments(matching: trimmed)) ?? []
    }
    
    
    @discardableResult
    func refresh(
        instrument: MarketInstrument,
        period: MarketChartPeriod,
        isBackgroundWatchlistRefresh: Bool = false
    ) async -> MarketQuoteSnapshot? {
        self.loadingInstrumentIDs.insert(instrument.instrumentID)
        defer { self.loadingInstrumentIDs.remove(instrument.instrumentID) }
        
        guard let snapshot = try? await self.client.fetchQuoteAndBars(for: instrument, period: period) else {
            return nil
        }
        var mergedBars = self.quotes[instrument.instrumentID]?.barsByPeriod ?? [:]
        for (p, bars) in snapshot.barsByPeriod {
            mergedBars[p] = bars
        }
        let merged = MarketQuoteSnapshot(
            instrument: snapshot.instrument,
            lastPrice: snapshot.lastPrice,
            previousClose: snapshot.previousClose,
            dayOpen: snapshot.dayOpen,
            high: snapshot.high,
            low: snapshot.low,
            volume: snapshot.volume,
            barsByPeriod: mergedBars,
            updatedAt: snapshot.updatedAt
        )
        self.quotes[instrument.instrumentID] = merged
        self.evictUnwatchedQuotesIfNeeded(preserving: instrument.instrumentID)
        if !isBackgroundWatchlistRefresh {
            self.selectedInstrumentName = "\(instrument.name) (\(instrument.symbol))"
            if self.isWatched(instrument.instrumentID) {
                self.database.updateWatchlistStockQuote(
                    instrumentID: instrument.instrumentID,
                    lastPrice: merged.lastPrice,
                    changePercent: merged.changePercent
                )
                self.reloadFromDatabase()
            }
        }
        return merged
    }
    
    
    private func evictUnwatchedQuotesIfNeeded(preserving activeID: String) {
        guard self.quotes.count > 32 else { return }
        let watchedIDs = Set(self.watchlist.map(\.instrumentID))
        for key in self.quotes.keys where key != activeID && !watchedIDs.contains(key) {
            self.quotes.removeValue(forKey: key)
            if self.quotes.count <= 32 { break }
        }
    }
    
    
    func refreshWatchlist(period: MarketChartPeriod = .day) async {
        let targets = self.watchlist.map(MarketInstrument.init(record:))
        let refreshed: [MarketQuoteSnapshot] = await withTaskGroup(of: MarketQuoteSnapshot?.self) { group in
            for inst in targets.prefix(8) {
                group.addTask {
                    await self.refresh(instrument: inst, period: period, isBackgroundWatchlistRefresh: true)
                }
            }
            var snapshots: [MarketQuoteSnapshot] = []
            for await snap in group {
                if let snap { snapshots.append(snap) }
            }
            return snapshots
        }
        if !refreshed.isEmpty {
            self.database.withTransaction {
                for snap in refreshed where self.isWatched(snap.instrument.instrumentID) {
                    self.database.updateWatchlistStockQuote(
                        instrumentID: snap.instrument.instrumentID,
                        lastPrice: snap.lastPrice,
                        changePercent: snap.changePercent
                    )
                }
            }
            self.memoryStore.reloadStocks()
            self.reloadFromDatabase()
        }
    }
}
