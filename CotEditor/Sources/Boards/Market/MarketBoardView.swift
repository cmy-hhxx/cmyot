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
    var onRevertToDocument: (() -> Void)? = nil
    var onOpenNote: ((String, String) -> Void)?
    
    @State private var marketService = CotMarketService.shared
    @State private var activeInstrument: MarketInstrument?
    @State private var searchText: String = ""
    @State private var isSearchExpanded: Bool = false
    @State private var isWatchlistRailVisible: Bool = true
    @State private var hoveredBarIndex: Int?
    @State private var searchTask: Task<Void, Never>?
    @State private var visibleBarCount: Int = 64
    @State private var barPanOffset: Int = 0
    @State private var dragStartOffset: Int?
    @State private var pinchBaseCount: Int?
    
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
        if self.boardState.marketPeriod == .intraday || all.count <= self.visibleBarCount {
            return all
        }
        let maxOffset = max(0, all.count - self.visibleBarCount)
        let clampedOffset = max(0, min(maxOffset, self.barPanOffset))
        let endIdx = all.count - clampedOffset
        let startIdx = max(0, endIdx - self.visibleBarCount)
        return Array(all[startIdx..<endIdx])
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
            .background(self.canvasBackground)
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
            self.barPanOffset = 0
            self.hoveredBarIndex = nil
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
    
    
    // MARK: - Interactive Candlestick & Intraday Canvas (Pinch Zoom + Pan + Crosshair Pills)
    
    private func chartCanvasSection(instrument: MarketInstrument, bars: [MarketBar]) -> some View {
        let activeIdx = self.hoveredBarIndex.flatMap { bars.indices.contains($0) ? $0 : nil } ?? (bars.count - 1)
        let inspectBar = bars[activeIdx]
        let ma5 = Self.movingAverage(bars: bars, period: 5)
        let ma10 = Self.movingAverage(bars: bars, period: 10)
        let ma20 = Self.movingAverage(bars: bars, period: 20)
        
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(inspectBar.timeLabel)
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(self.secondaryInk)
                
                if self.boardState.marketPeriod != .intraday {
                    self.ohlcChip("O", Self.formatPrice(inspectBar.open))
                    self.ohlcChip("H", Self.formatPrice(inspectBar.high))
                    self.ohlcChip("L", Self.formatPrice(inspectBar.low))
                    self.ohlcChip("C", Self.formatPrice(inspectBar.close))
                    
                    Spacer(minLength: 4)
                    
                    if let v5 = ma5[activeIdx] {
                        Text("MA5 \(Self.formatPrice(v5))")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Color(red: 0.96, green: 0.68, blue: 0.16))
                    }
                    if let v10 = ma10[activeIdx] {
                        Text("MA10 \(Self.formatPrice(v10))")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Color(red: 0.22, green: 0.72, blue: 0.94))
                    }
                    if let v20 = ma20[activeIdx] {
                        Text("MA20 \(Self.formatPrice(v20))")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.94))
                    }
                    
                    if self.allPeriodBars.count > 28 {
                        HStack(spacing: 2) {
                            Button {
                                self.visibleBarCount = min(120, self.visibleBarCount + 14)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(self.mutedInk)
                                    .frame(width: 20, height: 18)
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                self.visibleBarCount = max(24, self.visibleBarCount - 14)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(self.mutedInk)
                                    .frame(width: 20, height: 18)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 4)
                        .background(self.tokens.inset, in: Capsule())
                    }
                } else {
                    self.ohlcChip("P", Self.formatPrice(inspectBar.close))
                    Spacer(minLength: 4)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 28)
            
            GeometryReader { chartGeo in
                Canvas { context, size in
                    if self.boardState.marketPeriod == .intraday {
                        self.drawIntraday(
                            context: context,
                            size: size,
                            bars: bars,
                            previousClose: self.activeSnapshot?.previousClose ?? bars.first?.close ?? 0,
                            market: instrument.market,
                            hoverIndex: self.hoveredBarIndex
                        )
                    } else {
                        self.drawCandlesticks(
                            context: context,
                            size: size,
                            bars: bars,
                            ma5: ma5,
                            ma10: ma10,
                            ma20: ma20,
                            market: instrument.market,
                            hoverIndex: self.hoveredBarIndex
                        )
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                        case .active(let loc):
                            let plotW = max(1, chartGeo.size.width - 74)
                            let ratio = min(max((loc.x - 14) / plotW, 0), 1)
                            let idx = Int((ratio * CGFloat(max(0, bars.count - 1))).rounded())
                            self.hoveredBarIndex = bars.indices.contains(idx) ? idx : nil
                        case .ended:
                            self.hoveredBarIndex = nil
                    }
                }
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            if self.pinchBaseCount == nil {
                                self.pinchBaseCount = self.visibleBarCount
                            }
                            let base = self.pinchBaseCount ?? 64
                            let scaled = Int((CGFloat(base) / max(0.35, value.magnification)).rounded())
                            self.visibleBarCount = max(24, min(120, scaled))
                        }
                        .onEnded { _ in
                            self.pinchBaseCount = nil
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            guard self.boardState.marketPeriod != .intraday else { return }
                            if self.dragStartOffset == nil {
                                self.dragStartOffset = self.barPanOffset
                            }
                            let plotW = max(40, chartGeo.size.width - 74)
                            let pxPerBar = plotW / CGFloat(max(1, self.visibleBarCount))
                            let deltaBars = Int((value.translation.width / max(3, pxPerBar)).rounded())
                            let maxOffset = max(0, self.allPeriodBars.count - self.visibleBarCount)
                            let base = self.dragStartOffset ?? 0
                            self.barPanOffset = max(0, min(maxOffset, base + deltaBars))
                        }
                        .onEnded { _ in
                            self.dragStartOffset = nil
                        }
                )
            }
            .padding(.bottom, 10)
        }
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
    
    
    private func drawCandlesticks(
        context: GraphicsContext,
        size: CGSize,
        bars: [MarketBar],
        ma5: [Double?],
        ma10: [Double?],
        ma20: [Double?],
        market: MarketRegion,
        hoverIndex: Int?
    ) {
        let leftPad: CGFloat = 14
        let rightPad: CGFloat = 60
        let topPad: CGFloat = 10
        let bottomPad: CGFloat = 20
        let plotW = max(40, size.width - leftPad - rightPad)
        let totalH = max(80, size.height - topPad - bottomPad)
        let priceH = totalH * 0.74
        let volTop = topPad + priceH + 10
        let volH = max(16, totalH - priceH - 10)
        
        let maxPrice = bars.map(\.high).max() ?? 1
        let minPrice = bars.map(\.low).min() ?? 0
        let priceSpan = max(maxPrice - minPrice, maxPrice * 0.005, 0.0001)
        let maxVol = max(bars.map(\.volume).max() ?? 1, 1)
        
        func yForPrice(_ p: Double) -> CGFloat {
            topPad + priceH * (1 - CGFloat((p - minPrice) / priceSpan))
        }
        
        for step in 0...3 {
            let ratio = CGFloat(step) / 3.0
            let y = topPad + priceH * ratio
            var grid = Path()
            grid.move(to: CGPoint(x: leftPad, y: y))
            grid.addLine(to: CGPoint(x: leftPad + plotW, y: y))
            context.stroke(grid, with: .color(self.tokens.hairline), lineWidth: 0.6)
            
            let priceVal = maxPrice - priceSpan * Double(ratio)
            context.draw(
                Text(Self.formatPrice(priceVal))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(self.mutedInk),
                at: CGPoint(x: leftPad + plotW + 6, y: y),
                anchor: .leading
            )
        }
        
        let stepX = plotW / CGFloat(max(1, bars.count))
        let candleW = max(2.2, min(11, stepX * 0.64))
        
        for (idx, bar) in bars.enumerated() {
            let cx = leftPad + stepX * (CGFloat(idx) + 0.5)
            let tone = MarketTonePalette.directionColor(isRising: bar.isRising, market: market)
            
            var wick = Path()
            wick.move(to: CGPoint(x: cx, y: yForPrice(bar.high)))
            wick.addLine(to: CGPoint(x: cx, y: yForPrice(bar.low)))
            context.stroke(wick, with: .color(tone), lineWidth: 1.0)
            
            let openY = yForPrice(bar.open)
            let closeY = yForPrice(bar.close)
            let bodyTop = min(openY, closeY)
            let bodyHeight = max(1.5, abs(closeY - openY))
            let bodyRect = CGRect(x: cx - candleW * 0.5, y: bodyTop, width: candleW, height: bodyHeight)
            context.fill(Path(roundedRect: bodyRect, cornerRadius: 0.8), with: .color(tone))
            
            let vh = volH * CGFloat(bar.volume / maxVol)
            let volRect = CGRect(x: cx - candleW * 0.5, y: volTop + volH - vh, width: candleW, height: max(1, vh))
            context.fill(Path(volRect), with: .color(tone.opacity(0.42)))
        }
        
        let drawMA = { (series: [Double?], color: Color) in
            var path = Path()
            var started = false
            for (idx, val) in series.enumerated() {
                guard let val else { continue }
                let pt = CGPoint(x: leftPad + stepX * (CGFloat(idx) + 0.5), y: yForPrice(val))
                if !started {
                    path.move(to: pt)
                    started = true
                } else {
                    path.addLine(to: pt)
                }
            }
            if !path.isEmpty {
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }
        }
        drawMA(ma5, Color(red: 0.96, green: 0.68, blue: 0.16))
        drawMA(ma10, Color(red: 0.22, green: 0.72, blue: 0.94))
        drawMA(ma20, Color(red: 0.72, green: 0.45, blue: 0.94))
        
        if let hoverIndex, bars.indices.contains(hoverIndex) {
            let hx = leftPad + stepX * (CGFloat(hoverIndex) + 0.5)
            let hy = yForPrice(bars[hoverIndex].close)
            var cross = Path()
            cross.move(to: CGPoint(x: hx, y: topPad))
            cross.addLine(to: CGPoint(x: hx, y: volTop + volH))
            cross.move(to: CGPoint(x: leftPad, y: hy))
            cross.addLine(to: CGPoint(x: leftPad + plotW, y: hy))
            context.stroke(cross, with: .color(self.secondaryInk.opacity(0.45)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            
            // Floating right-axis price pill
            let priceBadge = CGRect(x: leftPad + plotW + 3, y: hy - 8.5, width: 52, height: 17)
            context.fill(RoundedRectangle(cornerRadius: 4, style: .continuous).path(in: priceBadge), with: .color(self.tokens.accent))
            context.draw(
                Text(Self.formatPrice(bars[hoverIndex].close))
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(self.tokens.onAccentInk),
                at: CGPoint(x: priceBadge.midX, y: priceBadge.midY),
                anchor: .center
            )
        }
    }
    
    
    private func drawIntraday(
        context: GraphicsContext,
        size: CGSize,
        bars: [MarketBar],
        previousClose: Double,
        market: MarketRegion,
        hoverIndex: Int?
    ) {
        let leftPad: CGFloat = 14
        let rightPad: CGFloat = 60
        let topPad: CGFloat = 12
        let bottomPad: CGFloat = 20
        let plotW = max(40, size.width - leftPad - rightPad)
        let plotH = max(80, size.height - topPad - bottomPad)
        
        let prices = bars.map(\.close)
        let ref = previousClose > 0 ? previousClose : (prices.first ?? 1)
        let maxDev = max(
            prices.map { abs($0 - ref) }.max() ?? 0.01,
            ref * 0.002
        )
        let high = ref + maxDev * 1.1
        let low = ref - maxDev * 1.1
        let span = max(high - low, 0.0001)
        
        func yForPrice(_ p: Double) -> CGFloat {
            topPad + plotH * (1 - CGFloat((p - low) / span))
        }
        
        let waterY = yForPrice(ref)
        var waterPath = Path()
        waterPath.move(to: CGPoint(x: leftPad, y: waterY))
        waterPath.addLine(to: CGPoint(x: leftPad + plotW, y: waterY))
        context.stroke(waterPath, with: .color(self.mutedInk.opacity(0.45)), style: StrokeStyle(lineWidth: 0.9, dash: [3, 4]))
        
        context.draw(
            Text(Self.formatPrice(ref))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(self.mutedInk),
            at: CGPoint(x: leftPad + plotW + 6, y: waterY),
            anchor: .leading
        )
        
        let lastPrice = prices.last ?? ref
        let tone = MarketTonePalette.directionColor(isRising: lastPrice >= ref, market: market)
        
        var linePath = Path()
        var fillPath = Path()
        for (idx, bar) in bars.enumerated() {
            let x = leftPad + plotW * CGFloat(idx) / CGFloat(max(1, bars.count - 1))
            let y = yForPrice(bar.close)
            if idx == 0 {
                linePath.move(to: CGPoint(x: x, y: y))
                fillPath.move(to: CGPoint(x: x, y: topPad + plotH))
                fillPath.addLine(to: CGPoint(x: x, y: y))
            } else {
                linePath.addLine(to: CGPoint(x: x, y: y))
                fillPath.addLine(to: CGPoint(x: x, y: y))
            }
            if idx == bars.count - 1 {
                fillPath.addLine(to: CGPoint(x: x, y: topPad + plotH))
                fillPath.closeSubpath()
            }
        }
        
        context.fill(
            fillPath,
            with: .linearGradient(
                Gradient(colors: [tone.opacity(0.18), tone.opacity(0.0)]),
                startPoint: CGPoint(x: 0, y: topPad),
                endPoint: CGPoint(x: 0, y: topPad + plotH)
            )
        )
        context.stroke(linePath, with: .color(tone), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        
        if let lastBar = bars.last {
            let lx = leftPad + plotW
            let ly = yForPrice(lastBar.close)
            context.fill(Path(ellipseIn: CGRect(x: lx - 3, y: ly - 3, width: 6, height: 6)), with: .color(tone))
        }
        
        if let hoverIndex, bars.indices.contains(hoverIndex) {
            let hx = leftPad + plotW * CGFloat(hoverIndex) / CGFloat(max(1, bars.count - 1))
            let hy = yForPrice(bars[hoverIndex].close)
            var cross = Path()
            cross.move(to: CGPoint(x: hx, y: topPad))
            cross.addLine(to: CGPoint(x: hx, y: topPad + plotH))
            cross.move(to: CGPoint(x: leftPad, y: hy))
            cross.addLine(to: CGPoint(x: leftPad + plotW, y: hy))
            context.stroke(cross, with: .color(self.secondaryInk.opacity(0.45)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            
            let priceBadge = CGRect(x: leftPad + plotW + 3, y: hy - 8.5, width: 52, height: 17)
            context.fill(RoundedRectangle(cornerRadius: 4, style: .continuous).path(in: priceBadge), with: .color(tone))
            context.draw(
                Text(Self.formatPrice(bars[hoverIndex].close))
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(self.tokens.onAccentInk),
                at: CGPoint(x: priceBadge.midX, y: priceBadge.midY),
                anchor: .center
            )
        }
    }
    
    
    // MARK: - Actions & Resolution
    
    private func bootstrapFromBoardState() {
        Task {
            if let explicitID = self.boardState.selectedInstrumentID,
               let resolved = await self.marketService.resolveInstrument(for: explicitID)
            {
                self.selectInstrument(resolved)
                return
            }
            let query = self.boardState.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty, let resolved = await self.marketService.resolveInstrument(for: query) {
                self.selectInstrument(resolved)
                return
            }
            if self.activeInstrument == nil, let first = self.marketService.watchlist.first {
                self.selectInstrument(MarketInstrument(record: first))
            }
            await self.marketService.refreshWatchlist(period: self.boardState.marketPeriod)
        }
    }
    
    
    private func selectInstrument(_ inst: MarketInstrument) {
        self.activeInstrument = inst
        self.boardState.selectedInstrumentID = inst.instrumentID
        self.boardState.dynamicTitle = inst.name
        self.hoveredBarIndex = nil
        self.barPanOffset = 0
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
