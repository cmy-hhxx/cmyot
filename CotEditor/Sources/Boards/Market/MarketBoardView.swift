//
//  MarketBoardView.swift
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
import SwiftUI

/// Embedded Market Watchlist & Real-Time K-Line / Intraday Board styled to fuse natively
/// with CotEditor's active editor paper and clean borderless chrome.
struct MarketBoardView: View {
    
    @Binding var boardState: PaneBoardState
    let tokens: StudioColorTokens
    var surfaceColor: Color? = nil
    var hasCustomBackground: Bool = false
    var onRevertToDocument: (() -> Void)? = nil
    var onOpenNote: ((String, String) -> Void)?
    
    @State private var marketService = CotMarketService.shared
    @State private var activeInstrument: MarketInstrument?
    @State private var searchText: String = ""
    @State private var isSearchExpanded: Bool = false
    @State private var isWatchlistRailVisible: Bool = true
    @State private var searchTask: Task<Void, Never>?
    @State private var showMovingAverages: Bool = true
    
    private var canvasBackground: Color {
        self.surfaceColor ?? self.tokens.canvasTop
    }
    
    private var secondaryInk: Color {
        self.tokens.isDark
            ? Color(red: 0.62, green: 0.65, blue: 0.72)
            : Color(red: 0.34, green: 0.37, blue: 0.44)
    }
    
    private var mutedInk: Color {
        self.tokens.isDark
            ? Color(red: 0.46, green: 0.50, blue: 0.57)
            : Color(red: 0.48, green: 0.52, blue: 0.58)
    }
    
    private var activeSnapshot: MarketQuoteSnapshot? {
        guard let inst = self.activeInstrument else { return nil }
        return self.marketService.quotes[inst.instrumentID]
    }
    
    private var allPeriodBars: [MarketBar] {
        guard let snap = self.activeSnapshot else { return [] }
        return snap.barsByPeriod[self.boardState.marketPeriod]
            ?? snap.barsByPeriod[.day]
            ?? snap.barsByPeriod[.intraday]
            ?? []
    }
    
    private var displayedBars: [MarketBar] {
        let all = self.allPeriodBars
        guard !all.isEmpty else { return [] }
        return all
    }
    
    
    var body: some View {
        GeometryReader { geo in
            let showsRail = self.isWatchlistRailVisible && geo.size.width >= 620
            HStack(spacing: 0) {
                if showsRail {
                    self.watchlistRail
                        .frame(width: 196)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Rectangle()
                        .fill(self.tokens.hairline)
                        .frame(width: 1)
                }
                
                self.klineStage(showsCompactStrip: !showsRail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(self.hasCustomBackground ? Color.clear : self.canvasBackground)
        }
        .onAppear {
            self.bootstrapFromBoardState()
        }
        .onChange(of: self.boardState.query) { _, _ in
            self.bootstrapFromBoardState()
        }
        .onChange(of: self.boardState.selectedInstrumentID) { _, _ in
            self.bootstrapFromBoardState()
        }
        .onChange(of: self.boardState.marketPeriod) { _, newPeriod in
            if let inst = self.activeInstrument {
                Task { _ = await self.marketService.refresh(instrument: inst, period: newPeriod) }
            }
        }
        .task(id: self.activeInstrument?.instrumentID ?? "idle") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let inst = self.activeInstrument else { break }
                guard NSApp?.isActive != false else { continue }
                _ = await self.marketService.refresh(instrument: inst, period: self.boardState.marketPeriod)
            }
        }
    }
    
    
    // MARK: - Left Watchlist & Search Rail
    
    private var watchlistRail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(self.mutedInk)
                TextField("", text: self.$searchText, prompt: Text(AppLanguage.text("代码 / 名称", en: "Symbol")))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(self.tokens.primaryInk)
                    .onSubmit {
                        self.triggerSearch(self.searchText, immediateSelect: true)
                    }
                    .onChange(of: self.searchText) { _, val in
                        self.scheduleSearch(val)
                    }
                if !self.searchText.isEmpty {
                    Button {
                        self.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(self.mutedInk)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            
            Rectangle()
                .fill(self.tokens.hairline)
                .frame(height: 1)
            
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    if !self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ForEach(self.marketService.searchResults) { item in
                            self.searchResultRow(item)
                        }
                    } else {
                        ForEach(self.marketService.watchlist) { stock in
                            self.watchlistRow(stock)
                        }
                    }
                }
                .padding(8)
            }
        }
        .background(Color.primary.opacity(self.tokens.isDark ? 0.03 : 0.02))
    }
    
    
    private func watchlistRow(_ stock: WatchlistStockRecord) -> some View {
        let inst = MarketInstrument(record: stock)
        let quote = self.marketService.quotes[stock.instrumentID]
        let price = quote?.lastPrice ?? stock.lastPrice
        let pct = quote?.changePercent ?? stock.lastChangePct
        let isSelected = self.activeInstrument?.instrumentID == stock.instrumentID
        let tone = MarketTonePalette.directionColor(isRising: (pct ?? 0) >= 0, market: inst.market)
        
        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                self.selectInstrument(inst)
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stock.name)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? self.tokens.primaryInk : self.secondaryInk)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(stock.symbol)
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(self.mutedInk)
                        Text(inst.namespace.displayName)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(self.mutedInk)
                    }
                }
                
                Spacer(minLength: 4)
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(price.map { Self.formatPrice($0) } ?? "—")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(price == nil ? self.mutedInk : tone)
                    Text(pct.map { Self.formatPercent($0) } ?? "—")
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(pct == nil ? self.mutedInk : tone.opacity(0.88))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSelected ? self.tokens.inset : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .contextMenu {
            Button(AppLanguage.text("移出自选", en: "Remove"), role: .destructive) {
                self.marketService.toggleWatch(inst)
            }
        }
    }
    
    
    private func searchResultRow(_ inst: MarketInstrument) -> some View {
        let watched = self.marketService.isWatched(inst.instrumentID)
        return HStack(spacing: 6) {
            Button {
                self.selectInstrument(inst)
                self.searchText = ""
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(inst.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineLimit(1)
                    Text("\(inst.namespace.displayName) · \(inst.symbol)")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(self.mutedInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Button {
                self.marketService.toggleWatch(inst)
            } label: {
                Image(systemName: watched ? "star.fill" : "plus.circle")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(watched ? self.tokens.accent : self.secondaryInk)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(self.tokens.inset.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    
    // MARK: - Main K-Line Stage
    
    private func klineStage(showsCompactStrip: Bool) -> some View {
        VStack(spacing: 0) {
            self.headerBar(showsCompactStrip: showsCompactStrip)
            
            if let inst = self.activeInstrument, let snap = self.activeSnapshot {
                Rectangle()
                    .fill(self.tokens.hairline.opacity(0.65))
                    .frame(height: 1)
                self.quoteStatsStrip(instrument: inst, snapshot: snap)
            }
            
            Rectangle()
                .fill(self.tokens.hairline)
                .frame(height: 1)
            
            if showsCompactStrip && !self.marketService.watchlist.isEmpty {
                self.compactWatchlistStrip
                Rectangle()
                    .fill(self.tokens.hairline)
                    .frame(height: 1)
            }
            
            if showsCompactStrip && !self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !self.marketService.searchResults.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(self.marketService.searchResults) { inst in
                            Button {
                                self.selectInstrument(inst)
                                self.searchText = ""
                            } label: {
                                Text("\(inst.name) (\(inst.symbol))")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(self.tokens.primaryInk)
                                    .padding(.horizontal, 9)
                                    .frame(height: 24)
                                    .background(self.tokens.inset, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                Rectangle()
                    .fill(self.tokens.hairline)
                    .frame(height: 1)
            }
            
            if let inst = self.activeInstrument {
                let bars = self.displayedBars
                if bars.isEmpty {
                    VStack(spacing: 8) {
                        if self.marketService.loadingInstrumentIDs.contains(inst.instrumentID) || self.boardState.isAnalyzingIntent {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(self.mutedInk)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    self.chartCanvasSection(instrument: inst, bars: bars)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(self.mutedInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    
    private var compactWatchlistStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(self.marketService.watchlist) { stock in
                    let inst = MarketInstrument(record: stock)
                    let isSelected = (self.activeInstrument?.instrumentID == stock.instrumentID)
                    let pct = self.marketService.quotes[stock.instrumentID]?.changePercent ?? stock.lastChangePct
                    let tone = MarketTonePalette.directionColor(isRising: (pct ?? 0) >= 0, market: inst.market)
                    Button {
                        withAnimation(.easeOut(duration: 0.14)) {
                            self.selectInstrument(inst)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(stock.name)
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? self.tokens.primaryInk : self.secondaryInk)
                            if let pct {
                                Text(Self.formatPercent(pct))
                                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                    .foregroundStyle(tone)
                            }
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(
                            isSelected ? self.tokens.inset : Color.clear,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
    }
    
    
    private func headerBar(showsCompactStrip: Bool) -> some View {
        let inst = self.activeInstrument
        let snap = self.activeSnapshot
        let tone = MarketTonePalette.directionColor(
            isRising: snap?.isRising ?? true,
            market: inst?.market ?? .hongKong
        )
        let watched = inst.map { self.marketService.isWatched($0.instrumentID) } ?? false
        let isRefreshing = inst.map { self.marketService.loadingInstrumentIDs.contains($0.instrumentID) } ?? false
        
        return HStack(spacing: 10) {
            if !showsCompactStrip {
                Button {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                        self.isWatchlistRailVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(self.isWatchlistRailVisible ? self.tokens.accentText : self.mutedInk)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            } else {
                Button {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                        self.isWatchlistRailVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(self.mutedInk)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            
            if let inst {
                HStack(spacing: 6) {
                    Text(inst.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineLimit(1)
                    Text(inst.symbol)
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(self.mutedInk)
                }
                
                if let snap {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(inst.market.currencyPrefix)\(Self.formatPrice(snap.lastPrice))")
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                            .foregroundStyle(tone)
                        
                        Text("\(Self.formatSignedAmount(snap.changeAmount))  \(Self.formatPercent(snap.changePercent))")
                            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(tone)
                    }
                }
            }
            
            Spacer(minLength: 6)
            
            if showsCompactStrip {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(self.mutedInk)
                    TextField("", text: self.$searchText, prompt: Text(AppLanguage.text("搜标的", en: "Symbol")))
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .frame(width: 78)
                        .onChange(of: self.searchText) { _, val in
                            self.scheduleSearch(val)
                        }
                        .onSubmit {
                            self.triggerSearch(self.searchText, immediateSelect: true)
                        }
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(self.tokens.inset, in: Capsule())
            }
            
            HStack(spacing: 2) {
                ForEach(MarketChartPeriod.allCases) { period in
                    let active = (self.boardState.marketPeriod == period)
                    Button {
                        withAnimation(.easeOut(duration: 0.14)) {
                            self.boardState.marketPeriod = period
                        }
                    } label: {
                        Text(period.label)
                            .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? self.tokens.onAccentInk : self.secondaryInk)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(active ? self.tokens.accent : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(2)
            .background(self.tokens.inset, in: Capsule())
            
            if self.boardState.marketPeriod != .intraday {
                Button {
                    self.showMovingAverages.toggle()
                } label: {
                    Text("MA")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(self.showMovingAverages ? self.tokens.onAccentInk : self.secondaryInk)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(self.showMovingAverages ? self.tokens.accent : self.tokens.inset, in: Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(AppLanguage.text("切换均线 MA5/MA10/MA20", en: "Toggle Moving Averages"))
            }
            
            if let inst {
                Button {
                    self.marketService.toggleWatch(inst)
                } label: {
                    Image(systemName: watched ? "star.fill" : "star")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(watched ? self.tokens.accent : self.mutedInk)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button {
                    Task { _ = await self.marketService.refresh(instrument: inst, period: self.boardState.marketPeriod) }
                } label: {
                    Image(systemName: isRefreshing ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(self.mutedInk)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                if let onOpenNote = self.onOpenNote {
                    Button {
                        let priceLine = snap.map {
                            "- 最新：\(inst.market.currencyPrefix)\(Self.formatPrice($0.lastPrice)) (\(Self.formatPercent($0.changePercent)))\n"
                        } ?? ""
                        let md = "# \(inst.name) (\(inst.symbol))\n\n\(priceLine)\n"
                        onOpenNote("\(inst.name) · 交易笔记", md)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(self.mutedInk)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            
            if let onRevertToDocument = self.onRevertToDocument {
                Button(action: onRevertToDocument) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(self.mutedInk)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(AppLanguage.text("切换回文档", en: "Back to Document"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }
    
    
    // MARK: - TradingView Lightweight Charts Canvas
    
    private func quoteStatsStrip(instrument: MarketInstrument, snapshot: MarketQuoteSnapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                self.ohlcChip(AppLanguage.text("昨收", en: "Prev"), Self.formatPrice(snapshot.previousClose))
                self.ohlcChip(AppLanguage.text("今开", en: "Open"), Self.formatPrice(snapshot.dayOpen))
                self.ohlcChip(AppLanguage.text("最高", en: "High"), Self.formatPrice(snapshot.high))
                self.ohlcChip(AppLanguage.text("最低", en: "Low"), Self.formatPrice(snapshot.low))
                if let turnover = snapshot.turnoverRate {
                    self.ohlcChip(AppLanguage.text("换手", en: "Turnover"), String(format: "%.2f%%", turnover))
                }
                if let pe = snapshot.peRatio {
                    self.ohlcChip("PE", String(format: "%.1f", pe))
                }
                if let cap = snapshot.marketCap {
                    self.ohlcChip(AppLanguage.text("市值", en: "Cap"), String(format: "%.1f亿", cap))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 28)
        }
        .background(Color.primary.opacity(self.tokens.isDark ? 0.02 : 0.015))
    }
    
    
    private func chartCanvasSection(instrument: MarketInstrument, bars: [MarketBar]) -> some View {
        TradingViewLightweightChartView(
            instrument: instrument,
            period: self.boardState.marketPeriod,
            bars: bars,
            previousClose: self.activeSnapshot?.previousClose ?? bars.first?.close ?? 0,
            isDark: self.tokens.isDark,
            showMovingAverages: self.showMovingAverages
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    
    private func ohlcChip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(self.mutedInk)
            Text(value)
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(self.tokens.primaryInk)
        }
    }
    
    
    // MARK: - Actions & Resolution
    
    private func bootstrapFromBoardState() {
        Task {
            if let explicitID = self.boardState.selectedInstrumentID,
               let resolved = await self.marketService.resolveInstrument(for: explicitID)
            {
                self.selectInstrument(resolved)
                await self.marketService.refreshWatchlist(period: .day)
                return
            }
            let query = self.boardState.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty, let resolved = await self.marketService.resolveInstrument(for: query) {
                self.selectInstrument(resolved)
                await self.marketService.refreshWatchlist(period: .day)
                return
            }
            if self.activeInstrument == nil {
                if let focus = self.marketService.watchlist.first(where: { $0.instrumentID == "sh:600703" })
                    ?? self.marketService.watchlist.first
                {
                    self.selectInstrument(MarketInstrument(record: focus))
                } else if let sanAn = MarketAliasCatalog.resolve("三安光电") {
                    self.selectInstrument(sanAn)
                }
            }
            await self.marketService.refreshWatchlist(period: self.boardState.marketPeriod)
        }
    }
    
    
    private func selectInstrument(_ inst: MarketInstrument) {
        self.activeInstrument = inst
        self.boardState.selectedInstrumentID = inst.instrumentID
        self.boardState.dynamicTitle = inst.name
        Task {
            _ = await self.marketService.refresh(instrument: inst, period: self.boardState.marketPeriod)
        }
    }
    
    
    private func scheduleSearch(_ query: String) {
        self.searchTask?.cancel()
        self.searchTask = Task {
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            await self.marketService.search(query: query)
        }
    }
    
    
    private func triggerSearch(_ query: String, immediateSelect: Bool) {
        Task {
            await self.marketService.search(query: query)
            if immediateSelect, let first = self.marketService.searchResults.first {
                self.selectInstrument(first)
                self.searchText = ""
            }
        }
    }
    
    
    // MARK: - Math & Formatters
    
    private static func movingAverage(bars: [MarketBar], period: Int) -> [Double?] {
        guard period > 0 else { return Array(repeating: nil, count: bars.count) }
        var result: [Double?] = Array(repeating: nil, count: bars.count)
        var runningSum = 0.0
        for idx in bars.indices {
            runningSum += bars[idx].close
            if idx >= period {
                runningSum -= bars[idx - period].close
            }
            if idx >= period - 1 {
                result[idx] = runningSum / Double(period)
            }
        }
        return result
    }
    
    
    private static func formatPrice(_ value: Double) -> String {
        if value >= 1000 { return String(format: "%.2f", value) }
        if value >= 10 { return String(format: "%.2f", value) }
        return String(format: "%.3f", value)
    }
    
    
    private static func formatPercent(_ value: Double) -> String {
        String(format: "%@%.2f%%", value >= 0 ? "+" : "", value)
    }
    
    
    private static func formatSignedAmount(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(Self.formatPrice(abs(value)))"
    }
}
