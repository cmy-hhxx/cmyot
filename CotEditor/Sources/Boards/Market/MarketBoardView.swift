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

/// Press-only Apple tactile button style (smooth spring compression on press, zero hover twitch).
private struct MarketTactileButtonStyle: ButtonStyle {
    
    var pressedScale: CGFloat = 0.94
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? self.pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.84 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.74), value: configuration.isPressed)
    }
}


/// Crisp Apple Stocks-style miniature trend sparkline drawn directly in SwiftUI Canvas.
private struct WatchlistSparklineView: View {
    
    let closes: [Double]
    let tone: Color
    
    var body: some View {
        Canvas { context, size in
            guard self.closes.count >= 2 else { return }
            let minV = self.closes.min() ?? 0
            let maxV = self.closes.max() ?? 1
            let span = max(maxV - minV, max(abs(maxV) * 0.002, 0.0001))
            let stepX = size.width / CGFloat(self.closes.count - 1)
            let padY: CGFloat = 1.5
            let usableH = max(1, size.height - padY * 2)
            
            var line = Path()
            for (idx, val) in self.closes.enumerated() {
                let x = CGFloat(idx) * stepX
                let y = padY + (1.0 - CGFloat((val - minV) / span)) * usableH
                if idx == 0 {
                    line.move(to: CGPoint(x: x, y: y))
                } else {
                    line.addLine(to: CGPoint(x: x, y: y))
                }
            }
            
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            
            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [self.tone.opacity(0.22), self.tone.opacity(0.0)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(
                line,
                with: .color(self.tone),
                style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: 34, height: 15)
        .allowsHitTesting(false)
    }
}


/// Subtle Safari / Apple Stocks-style top hairline loading bar during quote fetches.
private struct MarketChartLoadingHairline: View {
    
    let accentColor: Color
    @State private var phase: CGFloat = -0.35
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Capsule()
                .fill(self.accentColor.opacity(0.75))
                .frame(width: max(48, w * 0.28), height: 1.8)
                .offset(x: self.phase * w)
        }
        .frame(height: 2)
        .clipped()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: false)) {
                self.phase = 1.05
            }
        }
    }
}


/// Compact, precision-crafted Market Watchlist & Real-Time K-Line Board harmonized with CotEditor's editor paper.
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
    @State private var isWatchlistRailVisible: Bool = true
    @State private var searchTask: Task<Void, Never>?
    @State private var showMovingAverages: Bool = true
    @State private var hoveredRowID: String?
    @Namespace private var periodPillNamespace
    
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
    
    private var displayedBars: [MarketBar] {
        guard let snap = self.activeSnapshot else { return [] }
        return snap.barsByPeriod[self.boardState.marketPeriod]
            ?? snap.barsByPeriod[.day]
            ?? snap.barsByPeriod[.intraday]
            ?? []
    }
    
    
    var body: some View {
        GeometryReader { geo in
            let showsRail = self.isWatchlistRailVisible && geo.size.width >= 580
            HStack(spacing: 0) {
                if showsRail {
                    self.watchlistRail
                        .frame(width: 196)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Rectangle()
                        .fill(self.tokens.hairline)
                        .frame(width: 0.75)
                }
                
                self.klineStage(showsCompactStrip: !showsRail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showsRail)
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
    
    
    // MARK: - Compact Left Watchlist Rail
    
    private var watchlistRail: some View {
        let isSearching = !self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(self.mutedInk)
                TextField(AppLanguage.text("代码 / 名称", en: "Symbol"), text: self.$searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
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
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(self.mutedInk)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            
            Rectangle()
                .fill(self.tokens.hairline)
                .frame(height: 0.75)
            
            HStack(spacing: 4) {
                Text(isSearching ? AppLanguage.text("搜索结果", en: "Results") : AppLanguage.text("自选", en: "Watchlist"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(self.mutedInk)
                Spacer()
                Text("\(isSearching ? self.marketService.searchResults.count : self.marketService.watchlist.count)")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(self.mutedInk)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            
            Rectangle()
                .fill(self.tokens.hairline.opacity(0.65))
                .frame(height: 0.5)
            
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 1) {
                    if isSearching {
                        ForEach(self.marketService.searchResults) { item in
                            self.searchResultRow(item)
                        }
                    } else {
                        ForEach(self.marketService.watchlist) { stock in
                            self.watchlistRow(stock)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
            }
        }
        .background(Color.primary.opacity(self.tokens.isDark ? 0.025 : 0.018))
    }
    
    
    private func watchlistRow(_ stock: WatchlistStockRecord) -> some View {
        let inst = MarketInstrument(record: stock)
        let quote = self.marketService.quotes[stock.instrumentID]
        let price = quote?.lastPrice ?? stock.lastPrice
        let pct = quote?.changePercent ?? stock.lastChangePct
        let isSelected = self.activeInstrument?.instrumentID == stock.instrumentID
        let isHovered = self.hoveredRowID == stock.instrumentID
        let tone = MarketTonePalette.directionColor(isRising: (pct ?? 0) >= 0, market: inst.market)
        let sparkBars = (quote?.barsByPeriod[.intraday] ?? quote?.barsByPeriod[.day] ?? []).suffix(24)
        let sparkCloses = sparkBars.map(\.close)
        
        return Button {
            self.selectInstrument(inst)
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(stock.name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? self.tokens.primaryInk : self.secondaryInk)
                        .lineLimit(1)
                    Text(stock.symbol)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(self.mutedInk)
                        .lineLimit(1)
                }
                .frame(minWidth: 50, alignment: .leading)
                
                Spacer(minLength: 2)
                
                if sparkCloses.count >= 3 {
                    WatchlistSparklineView(closes: sparkCloses, tone: tone)
                }
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(price.map { Self.formatPrice($0) } ?? "—")
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText(value: price ?? 0))
                        .foregroundStyle(price == nil ? self.mutedInk : self.tokens.primaryInk)
                    Text(pct.map { Self.formatPercent($0) } ?? "—")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText(value: pct ?? 0))
                        .foregroundStyle(pct == nil ? self.mutedInk : tone)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(
                            (pct == nil ? Color.clear : tone.opacity(self.tokens.isDark ? 0.16 : 0.10)),
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5.5)
            .background(
                isSelected ? self.tokens.inset : (isHovered ? self.tokens.inset.opacity(0.55) : Color.clear),
                in: RoundedRectangle(cornerRadius: 6.5, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .strokeBorder(isSelected ? self.tokens.hairlineStrong : Color.clear, lineWidth: 0.6)
            )
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isSelected)
            .animation(.snappy(duration: 0.28), value: price ?? 0)
            .contentShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
        }
        .buttonStyle(MarketTactileButtonStyle(pressedScale: 0.98))
        .pointerStyle(.link)
        .onHover { hovering in
            self.hoveredRowID = hovering ? stock.instrumentID : (self.hoveredRowID == stock.instrumentID ? nil : self.hoveredRowID)
        }
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
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(inst.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineLimit(1)
                    Text("\(inst.namespace.displayName) · \(inst.symbol)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(self.mutedInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            Button {
                self.marketService.toggleWatch(inst)
            } label: {
                Text(watched ? AppLanguage.text("已选", en: "Saved") : AppLanguage.text("加自选", en: "Add"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(watched ? self.tokens.accentText : self.secondaryInk)
                    .padding(.horizontal, 6)
                    .frame(height: 19)
                    .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(self.tokens.inset.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    
    
    // MARK: - Main Precision K-Line Stage
    
    private func klineStage(showsCompactStrip: Bool) -> some View {
        VStack(spacing: 0) {
            self.headerBar(showsCompactStrip: showsCompactStrip)
            
            Rectangle()
                .fill(self.tokens.hairline)
                .frame(height: 0.75)
            
            if let inst = self.activeInstrument, let snap = self.activeSnapshot {
                self.quoteStatsStrip(instrument: inst, snapshot: snap)
                Rectangle()
                    .fill(self.tokens.hairline.opacity(0.7))
                    .frame(height: 0.5)
            }
            
            if showsCompactStrip && !self.marketService.watchlist.isEmpty {
                self.compactWatchlistStrip
                Rectangle()
                    .fill(self.tokens.hairline.opacity(0.7))
                    .frame(height: 0.5)
            }
            
            if showsCompactStrip && !self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !self.marketService.searchResults.isEmpty {
                self.compactSearchResultsStrip
                Rectangle()
                    .fill(self.tokens.hairline.opacity(0.7))
                    .frame(height: 0.5)
            }
            
            self.chartViewport
                .padding(8)
        }
    }
    
    
    private var chartViewport: some View {
        let isRefreshing = self.activeInstrument.map { self.marketService.loadingInstrumentIDs.contains($0.instrumentID) } ?? false
        return ZStack(alignment: .top) {
            Group {
                if let inst = self.activeInstrument {
                    let bars = self.displayedBars
                    if bars.isEmpty {
                        VStack(spacing: 6) {
                            if isRefreshing || self.boardState.isAnalyzingIntent {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(AppLanguage.text("暂无行情数据", en: "No Market Data"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(self.mutedInk)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        TradingViewLightweightChartView(
                            instrument: inst,
                            period: self.boardState.marketPeriod,
                            bars: bars,
                            previousClose: self.activeSnapshot?.previousClose ?? bars.first?.close ?? 0,
                            isDark: self.tokens.isDark,
                            showMovingAverages: self.showMovingAverages
                        )
                        .equatable()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    Text(AppLanguage.text("搜索代码或选择自选标的", en: "Select a symbol"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(self.mutedInk)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            
            if isRefreshing {
                MarketChartLoadingHairline(accentColor: self.tokens.accent)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isRefreshing)
        .background(
            self.hasCustomBackground
                ? self.tokens.card.opacity(self.tokens.isDark ? 0.44 : 0.62)
                : self.tokens.card.opacity(self.tokens.isDark ? 0.52 : 0.85),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                        self.selectInstrument(inst)
                    } label: {
                        HStack(spacing: 4) {
                            Text(stock.name)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? self.tokens.primaryInk : self.secondaryInk)
                            if let pct {
                                Text(Self.formatPercent(pct))
                                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                                    .foregroundStyle(tone)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 21)
                        .background(isSelected ? self.tokens.inset : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }
    
    
    private var compactSearchResultsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(self.marketService.searchResults) { inst in
                    Button {
                        self.selectInstrument(inst)
                        self.searchText = ""
                    } label: {
                        Text("\(inst.name) \(inst.symbol)")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(self.tokens.primaryInk)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
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
        
        return HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    self.isWatchlistRailVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(self.isWatchlistRailVisible && !showsCompactStrip ? self.tokens.primaryInk : self.mutedInk)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(MarketTactileButtonStyle())
            .pointerStyle(.link)
            
            if let inst {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(inst.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineLimit(1)
                    Text(inst.symbol)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced).monospacedDigit())
                        .foregroundStyle(self.mutedInk)
                }
                
                if let snap {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(inst.market.currencyPrefix)\(Self.formatPrice(snap.lastPrice))")
                            .font(.system(size: 14.5, weight: .bold).monospacedDigit())
                            .contentTransition(.numericText(value: snap.lastPrice))
                            .foregroundStyle(tone)
                        
                        Text("\(Self.formatSignedAmount(snap.changeAmount)) · \(Self.formatPercent(snap.changePercent))")
                            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                            .contentTransition(.numericText(value: snap.changePercent))
                            .foregroundStyle(tone)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(tone.opacity(self.tokens.isDark ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .animation(.snappy(duration: 0.28), value: snap.lastPrice)
                }
            }
            
            Spacer(minLength: 6)
            
            if showsCompactStrip {
                self.compactSearchField
            }
            
            self.periodSegmentedControl
            
            self.headerTrailingActions(inst: inst, snap: snap, watched: watched, isRefreshing: isRefreshing)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
    }
    
    
    private var compactSearchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5))
                .foregroundStyle(self.mutedInk)
            TextField(AppLanguage.text("搜标的", en: "Symbol"), text: self.$searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 72)
                .onChange(of: self.searchText) { _, val in
                    self.scheduleSearch(val)
                }
                .onSubmit {
                    self.triggerSearch(self.searchText, immediateSelect: true)
                }
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
    
    
    private var periodSegmentedControl: some View {
        HStack(spacing: 1) {
            ForEach(MarketChartPeriod.allCases) { period in
                let active = (self.boardState.marketPeriod == period)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        self.boardState.marketPeriod = period
                    }
                } label: {
                    Text(period.label)
                        .font(.system(size: 11, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? self.tokens.primaryInk : self.secondaryInk)
                        .padding(.horizontal, 7.5)
                        .frame(height: 20)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                    .fill(self.tokens.card)
                                    .shadow(color: Color.black.opacity(self.tokens.isDark ? 0.22 : 0.06), radius: 2, y: 0.5)
                                    .matchedGeometryEffect(id: "marketPeriodPill", in: self.periodPillNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .padding(2)
        .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
    }
    
    
    private func headerTrailingActions(
        inst: MarketInstrument?,
        snap: MarketQuoteSnapshot?,
        watched: Bool,
        isRefreshing: Bool
    ) -> some View {
        HStack(spacing: 6) {
            if self.boardState.marketPeriod != .intraday {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        self.showMovingAverages.toggle()
                    }
                } label: {
                    Text("MA")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(self.showMovingAverages ? self.tokens.accentText : self.mutedInk)
                        .padding(.horizontal, 6)
                        .frame(height: 22)
                        .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(MarketTactileButtonStyle())
                .pointerStyle(.link)
            }
            
            if let inst {
                Button {
                    self.marketService.toggleWatch(inst)
                } label: {
                    Text(watched ? AppLanguage.text("已自选", en: "Saved") : AppLanguage.text("加自选", en: "Watch"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(watched ? self.tokens.accentText : self.secondaryInk)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(MarketTactileButtonStyle())
                .pointerStyle(.link)
                
                Button {
                    Task { _ = await self.marketService.refresh(instrument: inst, period: self.boardState.marketPeriod) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isRefreshing ? self.tokens.accentText : self.mutedInk)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 0.85).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(MarketTactileButtonStyle())
                .pointerStyle(.link)
                .disabled(isRefreshing)
                
                if let onOpenNote = self.onOpenNote {
                    Button {
                        let priceLine = snap.map {
                            "- 最新：\(inst.market.currencyPrefix)\(Self.formatPrice($0.lastPrice)) (\(Self.formatPercent($0.changePercent)))\n"
                        } ?? ""
                        let md = "# \(inst.name) (\(inst.symbol))\n\n\(priceLine)\n"
                        onOpenNote("\(inst.name) · 交易笔记", md)
                    } label: {
                        Text(AppLanguage.text("笔记", en: "Note"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(self.secondaryInk)
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(MarketTactileButtonStyle())
                    .pointerStyle(.link)
                }
            }
            
            if let onRevertToDocument = self.onRevertToDocument {
                Button(action: onRevertToDocument) {
                    Text(AppLanguage.text("文档", en: "Doc"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(self.secondaryInk)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(MarketTactileButtonStyle())
                .pointerStyle(.link)
                .help(AppLanguage.text("切回文档编辑", en: "Back to Document"))
            }
        }
    }
    
    
    // MARK: - Compact Telemetry Strip
    
    private func quoteStatsStrip(instrument: MarketInstrument, snapshot: MarketQuoteSnapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                self.ohlcChip(AppLanguage.text("昨收", en: "Prev"), Self.formatPrice(snapshot.previousClose))
                self.ohlcChip(AppLanguage.text("今开", en: "Open"), Self.formatPrice(snapshot.dayOpen))
                self.ohlcChip(AppLanguage.text("最高", en: "High"), Self.formatPrice(snapshot.high))
                self.ohlcChip(AppLanguage.text("最低", en: "Low"), Self.formatPrice(snapshot.low))
                if let turnover = snapshot.turnoverRate {
                    self.ohlcChip(AppLanguage.text("换手", en: "Turn"), String(format: "%.2f%%", turnover))
                }
                if let pe = snapshot.peRatio {
                    self.ohlcChip("PE", String(format: "%.1f", pe))
                }
                if let cap = snapshot.marketCap {
                    self.ohlcChip(AppLanguage.text("市值", en: "Cap"), String(format: "%.1f亿", cap))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 24)
        }
        .background(Color.primary.opacity(self.tokens.isDark ? 0.018 : 0.012))
    }
    
    
    private func ohlcChip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3.5) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(self.mutedInk)
            Text(value)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .contentTransition(.numericText())
                .foregroundStyle(self.tokens.primaryInk)
        }
        .animation(.snappy(duration: 0.25), value: value)
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
    
    
    // MARK: - Formatters
    
    private static func formatPrice(_ value: Double) -> String {
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
