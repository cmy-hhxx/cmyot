//
//  DashboardNewsCenterView.swift
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

/// Xiaohongshu-style visual card NEWS workspace with harmonious native reading (no embedded AIHot webview)
/// and an AI follow-up chat powered by a LeiBox-style 3-stop Reasoning Effort Slider.
struct DashboardNewsCenterView: View {
    
    @Bindable var newsService: AIHotNewsService
    let tokens: StudioColorTokens
    let initialSelectedID: String?
    var isEmbeddedInPane: Bool = false
    var initialCategory: NewsFeedCategory? = nil
    var initialSearchQuery: String? = nil
    let onClose: () -> Void
    var onOpenExcerptDocument: ((String, String) -> Void)?
    
    @State private var selectedCategory: NewsFeedCategory
    @State private var searchText: String
    @State private var selectedItemID: String?
    @State private var gridPage: Int = 1
    @State private var knownTotalPages: Int = 1
    @State private var pageTurnDirection: Int = 1
    @FocusState private var isSearchFieldFocused: Bool
    @State private var reasoningEffort: NewsReasoningEffort = .balanced
    @State private var availableModels: [NewsChatModelOption] = []
    @State private var cachedModelOptions: [AgentModelOption] = []
    @State private var selectedModel: NewsChatModelOption?
    @State private var isModelPopoverOpen: Bool = false
    @State private var copiedMessageID: String?
    @State private var chatWidthFraction: CGFloat = 0.42
    @State private var dragStartChatFraction: CGFloat?
    @State private var isSplitDividerHovering: Bool = false
    @State private var lastAutoScrollAt: Date = .distantPast
    @State private var newsChatWebController = BeautifulAgentWebController()
    @State private var newsChatStreamListenerID: UUID? = nil
    @State private var newsQuotedExcerpt: String? = nil
    @State private var piKernel = PiKernelManager.shared
    
    init(
        newsService: AIHotNewsService,
        tokens: StudioColorTokens,
        initialSelectedID: String?,
        isEmbeddedInPane: Bool = false,
        initialCategory: NewsFeedCategory? = nil,
        initialSearchQuery: String? = nil,
        onClose: @escaping () -> Void,
        onOpenExcerptDocument: ((String, String) -> Void)? = nil
    ) {
        self.newsService = newsService
        self.tokens = tokens
        self.initialSelectedID = initialSelectedID
        self.isEmbeddedInPane = isEmbeddedInPane
        self.initialCategory = initialCategory
        self.initialSearchQuery = initialSearchQuery
        self.onClose = onClose
        self.onOpenExcerptDocument = onOpenExcerptDocument
        self._selectedCategory = State(initialValue: initialCategory ?? newsService.selectedCategory)
        self._searchText = State(initialValue: initialSearchQuery ?? "")
        self._selectedItemID = State(initialValue: initialSelectedID)
    }
    
    private let bodyFontSize: CGFloat = 15.5
    
    private var secondaryInk: Color {
        self.tokens.isDark
            ? Color(red: 0.604, green: 0.635, blue: 0.706)
            : Color(red: 0.306, green: 0.337, blue: 0.408)
    }
    
    private var mutedInk: Color {
        self.tokens.isDark
            ? Color(red: 0.455, green: 0.490, blue: 0.565)
            : Color(red: 0.451, green: 0.486, blue: 0.561)
    }
    
    private var displayedItems: [AIHotNewsItem] {
        let base = self.selectedCategory == .all
            ? self.newsService.items
            : self.newsService.items.filter { $0.resolvedCategory == self.selectedCategory }
        
        let query = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return base }
        return base.filter { item in
            item.title.lowercased().contains(query)
                || item.displayPublisherLabel.lowercased().contains(query)
                || (item.summary?.lowercased().contains(query) ?? false)
        }
    }
    
    private var selectedItem: AIHotNewsItem? {
        guard let id = self.selectedItemID else { return nil }
        return self.displayedItems.first(where: { $0.id == id })
            ?? self.newsService.items.first(where: { $0.id == id })
    }
    
    private var adjacentItems: (previous: AIHotNewsItem?, next: AIHotNewsItem?) {
        let list = self.displayedItems
        guard let curID = self.selectedItem?.id,
              let idx = list.firstIndex(where: { $0.id == curID })
        else { return (nil, nil) }
        let prev = idx > 0 ? list[idx - 1] : nil
        let next = (idx + 1) < list.count ? list[idx + 1] : nil
        return (prev, next)
    }
    
    
    var body: some View {
        VStack(spacing: 0) {
            self.topBar
            
            Rectangle()
                .fill(self.tokens.hairline)
                .frame(height: 1)
            
            if let item = self.selectedItem {
                self.detailAndChatStage(for: item)
                    .transition(.opacity)
            } else {
                self.xiaohongshuCardGridStage
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(self.tokens.canvasTop)
        .onAppear {
            self.reloadAvailableModels()
            self.syncSelectionSideEffects()
            if self.newsChatStreamListenerID == nil {
                let webCtrl = self.newsChatWebController
                self.newsChatStreamListenerID = self.newsService.addChatStreamPatchListener { itemID, patch in
                    if self.selectedItemID == itemID {
                        webCtrl.pushStreamPatch(patch)
                    }
                }
            }
            Task {
                await self.newsService.refreshIfNeeded()
            }
        }
        .onDisappear {
            if let id = self.newsChatStreamListenerID {
                self.newsService.removeChatStreamPatchListener(id)
                self.newsChatStreamListenerID = nil
            }
        }
        .onChange(of: self.selectedCategory) { _, _ in
            self.gridPage = 1
        }
        .onChange(of: self.searchText) { _, _ in
            self.gridPage = 1
        }
        .onChange(of: self.selectedItemID) { _, _ in
            self.isModelPopoverOpen = false
            self.newsQuotedExcerpt = nil
            self.reloadAvailableModels()
            self.syncSelectionSideEffects()
        }
        .onKeyPress(.leftArrow) {
            guard self.selectedItemID == nil, !self.isSearchFieldFocused else { return .ignored }
            if self.gridPage > 1 {
                self.turnGridPage(to: self.gridPage - 1)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            guard self.selectedItemID == nil, !self.isSearchFieldFocused else { return .ignored }
            self.turnGridPageByDelta(1)
            return .handled
        }
        .onKeyPress(.escape) {
            if self.isModelPopoverOpen {
                withAnimation(DashMotion.quick) {
                    self.isModelPopoverOpen = false
                }
                return .handled
            }
            if self.selectedItemID != nil {
                withAnimation(DashMotion.travel) {
                    self.selectedItemID = nil
                }
                return .handled
            }
            self.onClose()
            return .handled
        }
    }
    
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack(spacing: 12) {
            if !self.isEmbeddedInPane || self.selectedItemID != nil {
                Button {
                    if self.selectedItemID != nil {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                            self.selectedItemID = nil
                        }
                    } else {
                        self.onClose()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(self.selectedItemID != nil
                             ? AppLanguage.text("全部卡片", en: "All Cards")
                             : AppLanguage.text("返回", en: "Back"))
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(self.secondaryInk)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            
            if self.selectedItemID == nil {
                HStack(spacing: 2) {
                    ForEach(NewsFeedCategory.allCases) { category in
                        let isActive = (self.selectedCategory == category)
                        Button {
                            self.selectedCategory = category
                            self.newsService.selectedCategory = category
                        } label: {
                            Text(category == .xSocial ? "X" : category.label)
                                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? self.tokens.onAccentInk : self.secondaryInk)
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isActive ? self.tokens.accent : Color.clear)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
                .padding(3)
                .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                )
            } else if let item = self.selectedItem {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(self.tokens.primaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer(minLength: 8)
            
            if self.selectedItemID == nil {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(self.mutedInk)
                    TextField(AppLanguage.text("搜索资讯", en: "Search"), text: self.$searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(self.tokens.primaryInk)
                        .focused(self.$isSearchFieldFocused)
                        .frame(minWidth: 120, maxWidth: 190)
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
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                )
            } else {
                let neighbors = self.adjacentItems
                HStack(spacing: 4) {
                    Button {
                        if let prev = neighbors.previous {
                            withAnimation(DashMotion.quick) {
                                self.selectedItemID = prev.id
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(neighbors.previous != nil ? self.secondaryInk : self.mutedInk.opacity(0.35))
                            .frame(width: 28, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(neighbors.previous == nil)
                    .pointerStyle(neighbors.previous != nil ? .link : .default)
                    
                    Rectangle()
                        .fill(self.tokens.hairline)
                        .frame(width: 0.75, height: 14)
                    
                    Button {
                        if let next = neighbors.next {
                            withAnimation(DashMotion.quick) {
                                self.selectedItemID = next.id
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(neighbors.next != nil ? self.secondaryInk : self.mutedInk.opacity(0.35))
                            .frame(width: 28, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(neighbors.next == nil)
                    .pointerStyle(neighbors.next != nil ? .link : .default)
                }
                .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                )
                
                if let item = self.selectedItem {
                    Button {
                        let noteContent = self.newsService.buildMarkdownStudyNote(for: item)
                        if let handler = self.onOpenExcerptDocument {
                            handler(String(item.title.prefix(28)), noteContent)
                        } else {
                            CotAgentCoordinator.shared.openNewMarkdownDocument(
                                title: String(item.title.prefix(28)),
                                content: noteContent,
                                splitRight: true
                            )
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.text.badge.plus")
                                .font(.system(size: 11, weight: .medium))
                            Text(AppLanguage.text("存为笔记", en: "Save Note"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(self.secondaryInk)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    Button {
                        let summary = self.newsService.resolvedArticleBlocks(for: item)
                            .prefix(4)
                            .map(\.markdownText)
                            .joined(separator: "\n")
                        let quotePayload = "《\(item.title)》\n\(item.urlString)\n\(String(summary.prefix(600)))"
                        CotButlerManager.shared.requestOpenHub(
                            draft: AppLanguage.text("结合我的背景和市场情况，帮我深入分析一下这篇文章：", en: "Analyze this article in depth:"),
                            quote: quotePayload
                        )
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .medium))
                            Text(AppLanguage.text("转交总管", en: "Ask Butler"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(self.secondaryInk)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                
                if let url = self.selectedItem?.url {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 5) {
                            Text(AppLanguage.text("原文", en: "Original"))
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(self.secondaryInk)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            
            Button {
                Task {
                    await self.newsService.refreshIfNeeded(force: true)
                }
            } label: {
                Image(systemName: self.newsService.isLoading ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(self.secondaryInk)
                    .frame(width: 30, height: 30)
                    .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(self.newsService.isLoading)
            .pointerStyle(.link)
            .help(AppLanguage.text("刷新", en: "Refresh"))
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
    }
    
    
    // MARK: - Single-Screen Paginated Editorial Feed (2 Rows per Page · Zero Endless Scrolling)
    
    private static let pageTurnCurve = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)
    private static let cardTextFooterHeight: CGFloat = 82
    
    fileprivate static func stableSeed(for id: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
    
    static func waterfallCoverHeight(for item: AIHotNewsItem, cardWidth: CGFloat) -> CGFloat {
        let bucket = Int(Self.stableSeed(for: item.id) % 5)
        let ratios: [CGFloat] = [0.96, 1.02, 1.08, 1.14, 1.04]
        return (cardWidth * ratios[bucket]).rounded()
    }
    
    static func columnsForWidth(_ innerW: CGFloat) -> Int {
        if innerW >= 1220 { return 5 }
        if innerW >= 880 { return 4 }
        if innerW >= 600 { return 3 }
        return 2
    }
    
    private func turnGridPage(to targetPage: Int, totalPages: Int? = nil) {
        let clamped = totalPages.map { min(max(1, targetPage), $0) } ?? max(1, targetPage)
        guard clamped != self.gridPage else { return }
        self.pageTurnDirection = clamped > self.gridPage ? 1 : -1
        withAnimation(Self.pageTurnCurve) {
            self.gridPage = clamped
        }
    }
    
    private func turnGridPageByDelta(_ delta: Int) {
        let target = min(max(1, self.gridPage + delta), max(1, self.knownTotalPages))
        guard target != self.gridPage else { return }
        self.pageTurnDirection = delta >= 0 ? 1 : -1
        withAnimation(Self.pageTurnCurve) {
            self.gridPage = target
        }
    }
    
    private func prefetchAdjacentPageCovers(items: [AIHotNewsItem], safePage: Int, pageSize: Int) {
        guard !items.isEmpty, pageSize > 0 else { return }
        let start = max(0, (safePage - 1) * pageSize)
        let end = min(items.count, start + pageSize * 2)
        guard start < end else { return }
        for item in items[start..<end] {
            self.newsService.requestCoverLoad(for: item)
        }
    }
    
    private static func visiblePageNumbers(current: Int, total: Int) -> [Int] {
        guard total > 1 else { return [1] }
        if total <= 7 {
            return Array(1...total)
        }
        let windowRadius = 2
        var lower = max(2, current - windowRadius)
        var upper = min(total - 1, current + windowRadius)
        if current <= 3 {
            upper = min(total - 1, 5)
        } else if current >= total - 2 {
            lower = max(2, total - 4)
        }
        var result: [Int] = [1]
        if lower > 2 { result.append(-1) }
        result.append(contentsOf: lower...upper)
        if upper < total - 1 { result.append(-2) }
        result.append(total)
        return result
    }
    
    private var xiaohongshuCardGridStage: some View {
        let items = self.displayedItems
        return GeometryReader { geo in
            let innerW = min(1320, max(320, geo.size.width - 48))
            let colCount = Self.columnsForWidth(innerW)
            let colSpacing: CGFloat = 16
            let rowSpacing: CGFloat = 16
            let topPad: CGFloat = 16
            let bottomPad: CGFloat = 12
            let estAvailH = max(200, geo.size.height - 48 - topPad - bottomPad)
            let rowCount: Int = if estAvailH >= 980 {
                4
            } else if estAvailH >= 660 {
                3
            } else if estAvailH >= 340 {
                2
            } else {
                1
            }
            let pageSize = max(1, colCount * rowCount)
            let totalPages = max(1, Int(ceil(Double(items.count) / Double(pageSize))))
            let safePage = min(max(1, self.gridPage), totalPages)
            let startIdx = (safePage - 1) * pageSize
            let endIdx = min(items.count, startIdx + pageSize)
            let pageItems: [AIHotNewsItem] = (startIdx < endIdx) ? Array(items[startIdx..<endIdx]) : []
            
            let pagerH: CGFloat = totalPages > 1 ? 48 : 12
            let cardWidth = max(120, (innerW - CGFloat(colCount - 1) * colSpacing) / CGFloat(colCount))
            
            // Dynamically size rows & cover height to fill the viewport cleanly with zero bottom void and zero scrollbar
            let availGridH = max(180, geo.size.height - pagerH - topPad - bottomPad)
            let idealCardH = floor((availGridH - CGFloat(max(0, rowCount - 1)) * rowSpacing) / CGFloat(rowCount))
            let maxRatioCoverH = max(120, (cardWidth * 1.08).rounded())
            let coverHeight = min(maxRatioCoverH, max(86, idealCardH - Self.cardTextFooterHeight))
            let rows: [[AIHotNewsItem]] = (0..<rowCount).compactMap { rowIdx in
                let rStart = rowIdx * colCount
                guard rStart < pageItems.count else { return nil }
                let rEnd = min(pageItems.count, rStart + colCount)
                return Array(pageItems[rStart..<rEnd])
            }
            
            if items.isEmpty {
                VStack(spacing: 10) {
                    Text(self.newsService.isLoading
                         ? AppLanguage.text("正在加载资讯…", en: "Loading articles…")
                         : AppLanguage.text("暂无匹配资讯", en: "No articles"))
                        .font(.system(size: 13))
                        .foregroundStyle(self.mutedInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    let pageGrid = VStack(alignment: .leading, spacing: rowSpacing) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, rowItems in
                            self.paginatedCardRow(
                                rowItems: rowItems,
                                colCount: colCount,
                                colSpacing: colSpacing,
                                cardWidth: cardWidth,
                                coverHeight: coverHeight
                            )
                        }
                    }
                    .frame(width: innerW, height: availGridH, alignment: .topLeading)
                    .id("news-page-\(self.selectedCategory.rawValue)-\(safePage)")
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(x: CGFloat(self.pageTurnDirection) * 20)),
                            removal: .opacity.combined(with: .offset(x: CGFloat(-self.pageTurnDirection) * 16))
                        )
                    )
                    
                    ZStack {
                        pageGrid
                            .padding(.horizontal, 24)
                            .padding(.top, topPad)
                            .padding(.bottom, bottomPad)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        
                        if totalPages > 1 {
                            NewsGridWheelPagerRepresentable { delta in
                                let next = safePage + delta
                                guard next >= 1 && next <= totalPages else { return }
                                self.turnGridPage(to: next, totalPages: totalPages)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    
                    if totalPages > 1 {
                        self.editorialPaginationBar(
                            safePage: safePage,
                            totalPages: totalPages,
                            totalItems: items.count,
                            innerWidth: innerW
                        )
                        .frame(height: pagerH)
                    }
                }
                .onAppear {
                    self.knownTotalPages = totalPages
                    if self.gridPage != safePage {
                        self.gridPage = safePage
                    }
                    self.prefetchAdjacentPageCovers(items: items, safePage: safePage, pageSize: pageSize)
                }
                .onChange(of: totalPages) { _, newTotal in
                    self.knownTotalPages = newTotal
                    if self.gridPage > newTotal {
                        self.gridPage = newTotal
                    }
                }
                .onChange(of: safePage) { _, newPage in
                    if self.gridPage > totalPages {
                        self.gridPage = totalPages
                    }
                    self.prefetchAdjacentPageCovers(items: items, safePage: newPage, pageSize: pageSize)
                }
                .onChange(of: items.count) { _, _ in
                    self.knownTotalPages = totalPages
                    if self.gridPage > totalPages {
                        self.gridPage = totalPages
                    }
                    self.prefetchAdjacentPageCovers(items: items, safePage: min(self.gridPage, totalPages), pageSize: pageSize)
                }
            }
        }
    }
    
    @ViewBuilder
    private func paginatedCardRow(
        rowItems: [AIHotNewsItem],
        colCount: Int,
        colSpacing: CGFloat,
        cardWidth: CGFloat,
        coverHeight: CGFloat
    ) -> some View {
        HStack(alignment: .top, spacing: colSpacing) {
            ForEach(rowItems) { item in
                XiaohongshuNewsCard(
                    item: item,
                    cover: self.newsService.cachedCoverImage(for: item),
                    coverHeight: coverHeight,
                    isRead: self.newsService.isRead(item),
                    hasAIBrief: !(self.newsService.aiBriefs[item.id] ?? "").isEmpty,
                    tokens: self.tokens,
                    secondaryInk: self.secondaryInk,
                    mutedInk: self.mutedInk,
                    onAppearLoadCover: {
                        self.newsService.requestCoverLoad(for: item)
                    }
                ) {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                        self.selectedItemID = item.id
                    }
                }
                .equatable()
                .frame(width: cardWidth)
            }
            if rowItems.count < colCount {
                ForEach(0..<(colCount - rowItems.count), id: \.self) { _ in
                    Color.clear
                        .frame(width: cardWidth, height: coverHeight + Self.cardTextFooterHeight)
                }
            }
        }
    }
    
    private func editorialPaginationBar(
        safePage: Int,
        totalPages: Int,
        totalItems: Int,
        innerWidth: CGFloat
    ) -> some View {
        let pages = Self.visiblePageNumbers(current: safePage, total: totalPages)
        
        return HStack(spacing: 12) {
            Text(AppLanguage.text("共 \(totalItems) 篇", en: "\(totalItems) items"))
                .font(.system(size: 11.5, weight: .medium, design: .monospaced).monospacedDigit())
                .foregroundStyle(self.mutedInk)
            
            Spacer(minLength: 8)
            
            HStack(spacing: 5) {
                Button {
                    self.turnGridPage(to: safePage - 1, totalPages: totalPages)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text(AppLanguage.text("上一页", en: "Prev"))
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(safePage > 1 ? self.tokens.primaryInk : self.mutedInk.opacity(0.38))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(self.tokens.hairline, lineWidth: 0.8))
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(safePage <= 1)
                .pointerStyle(safePage > 1 ? .link : .default)
                
                ForEach(pages, id: \.self) { p in
                    if p < 0 {
                        Text("…")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(self.mutedInk)
                            .frame(width: 20, height: 28)
                    } else {
                        let isCurrent = (p == safePage)
                        Button {
                            self.turnGridPage(to: p, totalPages: totalPages)
                        } label: {
                            Text("\(p)")
                                .font(.system(size: 11.5, weight: isCurrent ? .semibold : .medium, design: .monospaced).monospacedDigit())
                                .foregroundStyle(isCurrent ? self.tokens.onAccentInk : self.secondaryInk)
                                .frame(minWidth: 28, minHeight: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isCurrent ? self.tokens.accent : self.tokens.card)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(isCurrent ? Color.clear : self.tokens.hairline, lineWidth: 0.8)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
                
                Button {
                    self.turnGridPage(to: safePage + 1, totalPages: totalPages)
                } label: {
                    HStack(spacing: 4) {
                        Text(AppLanguage.text("下一页", en: "Next"))
                            .font(.system(size: 11.5, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(safePage < totalPages ? self.tokens.primaryInk : self.mutedInk.opacity(0.38))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(self.tokens.hairline, lineWidth: 0.8))
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(safePage >= totalPages)
                .pointerStyle(safePage < totalPages ? .link : .default)
            }
            
            Spacer(minLength: 8)
            
            Text(AppLanguage.text("滚轮 / ← → 翻页", en: "Swipe / ← →"))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(self.mutedInk.opacity(0.75))
        }
        .frame(width: innerWidth)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }
    
    
    // MARK: - Balanced Native Editorial Reader + Polished AI Chat Split
    
    private func detailAndChatStage(for item: AIHotNewsItem) -> some View {
        let blocks = self.newsService.resolvedArticleBlocks(for: item)
        let summaryText = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isLoadingArticle = self.newsService.loadingArticleIDs.contains(item.id)
            || (blocks.isEmpty && summaryText.isEmpty && !self.newsService.hasFinishedDetailFetch(for: item.id))
        let neighbors = self.adjacentItems
        // Suppress synthetic auto-generated OG score-card banners (e.g. aihot.news dark headline cards) inside detail reader
        let readerCover: NSImage? = AIHotNewsService.isSyntheticOGCardURL(item.coverURLString)
            ? nil
            : self.newsService.coverImage(for: item)
        let bui = BeautifulUITokens.resolve(isDark: self.tokens.isDark)
        let quoteHandler: (String) -> Void = { snippet in
            let clean = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            self.newsQuotedExcerpt = String(clean.prefix(500))
            self.newsChatWebController.injectDraft("", quote: self.newsQuotedExcerpt)
            self.newsChatWebController.focusComposer()
        }
        
        return GeometryReader { geo in
            let isCompact = geo.size.width < 840
            if isCompact {
                VStack(spacing: 0) {
                    NewsEditorialArticlePane(
                        item: item,
                        cover: readerCover,
                        blocks: blocks,
                        isLoadingArticle: isLoadingArticle,
                        previousItem: neighbors.previous,
                        nextItem: neighbors.next,
                        bodyFontSize: self.bodyFontSize,
                        tokens: self.tokens,
                        bui: bui,
                        secondaryInk: self.secondaryInk,
                        mutedInk: self.mutedInk,
                        onSelectItem: { nextID in
                            withAnimation(DashMotion.quick) {
                                self.selectedItemID = nextID
                            }
                        },
                        onQuoteToAI: quoteHandler
                    )
                    .equatable()
                    .frame(height: max(220, geo.size.height * 0.50))
                    
                    Rectangle()
                        .fill(bui.line)
                        .frame(height: 1)
                    
                    self.aiChatPane(for: item, isCenteredCard: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // Harmonized split stage (~56 / 44) sharing Beautiful UI surface tokens seamlessly
                let useCenteredCard = !self.isEmbeddedInPane && geo.size.width >= 940
                let stageWidth = useCenteredCard ? min(1240, geo.size.width - 44) : geo.size.width
                let minChatWidth: CGFloat = 360
                let maxChatWidth: CGFloat = max(minChatWidth, min(stageWidth * 0.48, stageWidth - 440))
                let proposedChatWidth = stageWidth * self.chatWidthFraction
                let chatWidth = min(maxChatWidth, max(minChatWidth, proposedChatWidth))
                
                let splitContent = HStack(spacing: 0) {
                    NewsEditorialArticlePane(
                        item: item,
                        cover: readerCover,
                        blocks: blocks,
                        isLoadingArticle: isLoadingArticle,
                        previousItem: neighbors.previous,
                        nextItem: neighbors.next,
                        bodyFontSize: self.bodyFontSize,
                        tokens: self.tokens,
                        bui: bui,
                        secondaryInk: self.secondaryInk,
                        mutedInk: self.mutedInk,
                        onSelectItem: { nextID in
                            withAnimation(DashMotion.quick) {
                                self.selectedItemID = nextID
                            }
                        },
                        onQuoteToAI: quoteHandler
                    )
                    .equatable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    self.newsSplitDivider(totalWidth: stageWidth, bui: bui)
                    
                    self.aiChatPane(for: item, isCenteredCard: useCenteredCard)
                        .frame(width: chatWidth)
                        .frame(maxHeight: .infinity)
                }
                .transaction { tx in
                    if self.dragStartChatFraction != nil {
                        tx.animation = nil
                    }
                }
                .coordinateSpace(name: "newsSplitStage")
                
                if useCenteredCard {
                    splitContent
                        .frame(width: stageWidth)
                        .frame(maxHeight: .infinity)
                        .background(bui.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(bui.line, lineWidth: 1)
                        )
                        .shadow(
                            color: Color.black.opacity(self.tokens.isDark ? 0.36 : 0.06),
                            radius: 20,
                            x: 0,
                            y: 8
                        )
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    splitContent
                }
            }
        }
    }
    
    private func newsSplitDivider(totalWidth: CGFloat, bui: BeautifulUITokens) -> some View {
        let isActive = self.isSplitDividerHovering || self.dragStartChatFraction != nil
        return ZStack {
            Rectangle()
                .fill(isActive ? bui.accent.opacity(0.55) : bui.line)
                .frame(width: isActive ? 2 : 1)
        }
        .frame(width: 6)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering && !self.isSplitDividerHovering {
                NSCursor.resizeLeftRight.push()
            } else if !hovering && self.isSplitDividerHovering {
                NSCursor.pop()
            }
            self.isSplitDividerHovering = hovering
        }
        .onDisappear {
            if self.isSplitDividerHovering {
                NSCursor.pop()
                self.isSplitDividerHovering = false
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("newsSplitStage"))
                .onChanged { value in
                    if self.dragStartChatFraction == nil {
                        self.dragStartChatFraction = self.chatWidthFraction
                    }
                    let startFraction = self.dragStartChatFraction ?? self.chatWidthFraction
                    let deltaFraction = -value.translation.width / max(totalWidth, 1)
                    self.chatWidthFraction = min(0.48, max(0.34, startFraction + deltaFraction))
                }
                .onEnded { _ in
                    self.dragStartChatFraction = nil
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(DashMotion.travel) {
                self.chatWidthFraction = 0.42
            }
        }
    }
    
    
    // MARK: - Right Unified Beautiful UI NEWS AI Companion (Pi 1.6+ RPC Kernel)
    
    private func aiChatPane(for item: AIHotNewsItem, isCenteredCard: Bool = false) -> some View {
        let bui = BeautifulUITokens.resolve(isDark: self.tokens.isDark)
        let hostState = self.buildNewsAgentHostState(for: item)
        let callbacks = self.buildNewsAgentCallbacks(for: item)
        
        return BeautifulAgentWebView(
            state: hostState,
            controller: self.newsChatWebController,
            callbacks: callbacks
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isCenteredCard ? bui.surface : bui.page)
    }
    
    
    private func buildNewsAgentHostState(for item: AIHotNewsItem) -> BeautifulAgentHostStatePayload {
        let messages = self.newsService.chatMessages(for: item)
        let isStreaming = (self.newsService.streamingChatItemID == item.id)
        let streamingMsgID = isStreaming ? self.newsService.streamingChatMessageID : nil
        let botStore = AIBotStore.shared
        let botName = botStore.resolvedName(for: .readingCompanion)
        let botNick = botStore.resolvedNickname(for: .readingCompanion)
        let botAvatar = botStore.resolvedAvatarImage(for: .readingCompanion, pointSize: 72)
        let avatarDataURL = BeautifulAgentUIBundle.avatarDataURL(from: botAvatar)
        let modelOptions = self.cachedModelOptions.isEmpty ? self.unifiedModelOptions() : self.cachedModelOptions
        let selectedTitle = self.selectedModel?.displayName
            ?? self.availableModels.first?.displayName
            ?? AIProvider.openCodeGo.defaultModel
        
        let mappedMessages: [BeautifulAgentMessagePayload] = messages.map { msg in
            let isActiveStream = (msg.id == streamingMsgID)
            let chips = msg.toolChips?.map {
                BeautifulAgentToolReceipt(id: "nc-\(msg.id)-\($0)", label: $0, detail: nil, status: "done")
            }
            return BeautifulAgentMessagePayload(
                id: msg.id,
                role: msg.role == .user ? "user" : "assistant",
                text: msg.text,
                thinking: msg.thinking,
                thinkingDurationMs: msg.thinkingDurationMs,
                steps: msg.steps,
                toolChips: chips,
                followUps: msg.followUps,
                isStreaming: isActiveStream,
                isError: msg.isError,
                quoteContext: msg.quoteContext,
                createdAt: msg.createdAt.timeIntervalSince1970 * 1000
            )
        }
        
        let mappedModels: [BeautifulAgentModelPayload] = modelOptions.map { opt in
            let lower = opt.modelID.lowercased()
            let isFlagship = lower.contains("opus") || lower.contains("gpt-5") || lower.contains("glm-5") || lower.contains("deepseek-v4") || lower.contains("gemini-2.5-pro")
            let tag: String? = if lower.contains("flash") || lower.contains("haiku") || lower.contains("mini") {
                AppLanguage.text("快推", en: "Fast")
            } else if lower.contains("opus") || lower.contains("pro") || lower.contains("reasoner") {
                AppLanguage.text("深度", en: "Deep")
            } else {
                nil
            }
            return BeautifulAgentModelPayload(
                id: opt.id,
                modelID: opt.modelID,
                title: opt.title,
                endpointID: opt.endpointID?.uuidString,
                tag: tag,
                isFlagship: isFlagship
            )
        }
        
        let effortRaw: String = switch self.reasoningEffort {
            case .simple: "simple"
            case .balanced: "balanced"
            case .deep: "deep"
        }
        
        let suggestions: [BeautifulAgentSuggestionPayload] = [
            .init(
                id: "n-tldr",
                label: AppLanguage.text("一分钟核心精读", en: "1-min core takeaways"),
                prompt: AppLanguage.text("请用一分钟能看完的结构化要点提炼这篇文章的核心事实、关键数字与结论。", en: "Extract the key facts, numbers, and conclusion in concise bullets."),
                icon: "spark"
            ),
            .init(
                id: "n-sharp",
                label: AppLanguage.text("犀利点评与深层逻辑", en: "Sharp critique & logic"),
                prompt: AppLanguage.text("你怎么看这件事？请给出犀利点评、背后的利益/技术逻辑以及对行业的中长期影响。", en: "Give sharp commentary on the deeper technical and industry logic behind this story."),
                icon: "bolt"
            ),
            .init(
                id: "n-stock",
                label: AppLanguage.text("查关联股票与市场影响", en: "Check related stocks"),
                prompt: AppLanguage.text("请识别这篇文章涉及的关键上市公司或产业链龙头，调用行情工具查询它们的最新实时股价与近期走势，并分析潜在市场影响。", en: "Identify related public companies, look up their live stock quotes, and analyze potential market impact."),
                icon: "market"
            ),
            .init(
                id: "n-risk",
                label: AppLanguage.text("反面视角与潜在风险", en: "Counter-view & risks"),
                prompt: AppLanguage.text("跳出新闻本身的立场，从反面视角指出这件事被忽视的风险、局限或潜在反转可能。", en: "Provide a contrarian perspective highlighting overlooked risks and limitations."),
                icon: "shield"
            ),
        ]
        
        let slashCommands: [BeautifulAgentSlashCommandPayload] = [
            .init(key: "tldr", name: "/tldr", desc: AppLanguage.text("提炼核心事实与关键数字", en: "Quick key takeaways"), insertText: AppLanguage.text("用 3-5 条要点提炼这篇文章最核心的事实与数字", en: "Summarize the core facts in 3-5 bullets")),
            .init(key: "stock", name: "/stock", desc: AppLanguage.text("查文中涉及公司的实时股价", en: "Lookup related stock quotes"), insertText: AppLanguage.text("查一下文中涉及公司的最新股价和近期走势，并分析市场影响", en: "Lookup live quotes for companies mentioned")),
            .init(key: "note", name: "/note", desc: AppLanguage.text("生成结构化阅读笔记并新建文档", en: "Create structured study note"), insertText: AppLanguage.text("请把这篇文章和核心观点整理成结构化 Markdown 阅读笔记，并直接新建一篇文档保存", en: "Create a structured Markdown note for this article")),
        ]
        
        let sourceNote = item.displayPublisherLabel.isEmpty ? item.resolvedCategory.label : item.displayPublisherLabel
        
        return BeautifulAgentHostStatePayload(
            mode: "news",
            isDark: self.tokens.isDark,
            locale: AppLanguage.current == .simplifiedChinese ? "zh" : "en",
            botName: botName,
            botNickname: botNick,
            botAvatarDataURL: avatarDataURL,
            piAvailable: self.piKernel.canRunRPC,
            piStatusLabel: self.piKernel.statusSummary,
            isPinnedPanel: false,
            isDockedPane: true,
            showSidebar: false,
            sessions: [],
            activeSessionID: item.id,
            messages: mappedMessages,
            isStreaming: isStreaming,
            streamingStatusLabel: isStreaming && !self.newsService.streamingChatStatusLabel.isEmpty
                ? self.newsService.streamingChatStatusLabel
                : nil,
            errorMessage: self.newsService.chatErrorMessage,
            placeholder: AppLanguage.text("针对这篇资讯追问，点左侧段落可「引用提问」…", en: "Ask about this article, or quote any paragraph..."),
            greetingName: nil,
            greetingSubtitle: self.piKernel.canRunRPC
                ? AppLanguage.text("可直接精读、犀利点评、实时查关联股价或存为笔记", en: "Summarize, critique, look up live stock quotes, or save notes")
                : AppLanguage.text("点击下方快捷问题，或直接输入你想了解的角度", en: "Pick a prompt below or ask anything about this article"),
            articleTitle: item.title,
            articleSource: sourceNote,
            quotedExcerpt: self.newsQuotedExcerpt,
            availableModels: mappedModels,
            selectedModelID: selectedTitle,
            selectedModelTitle: selectedTitle,
            effort: effortRaw,
            suggestions: suggestions,
            contextSources: [],
            slashCommands: slashCommands
        )
    }
    
    
    private func buildNewsAgentCallbacks(for item: AIHotNewsItem) -> BeautifulAgentWebActionCallbacks {
        let botStore = AIBotStore.shared
        var cb = BeautifulAgentWebActionCallbacks()
        cb.onSend = { prompt, quote in
            guard self.newsService.streamingChatItemID == nil else { return }
            let effectiveQuote = quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? self.newsQuotedExcerpt
                : quote
            self.newsQuotedExcerpt = nil
            Task {
                await self.newsService.sendChatFollowUp(
                    prompt,
                    for: item,
                    quote: effectiveQuote,
                    effort: self.reasoningEffort,
                    selectedModel: self.selectedModel
                )
            }
        }
        cb.onAbort = {
            self.newsService.abortChat()
        }
        cb.onRetry = {
            self.newsService.retryLastChat(
                for: item,
                effort: self.reasoningEffort,
                selectedModel: self.selectedModel
            )
        }
        cb.onClearChat = {
            self.newsService.clearChat(for: item.id)
        }
        cb.onClearQuote = {
            self.newsQuotedExcerpt = nil
        }
        cb.onSelectModel = { model in
            let epUUID = model.endpointID.flatMap(UUID.init(uuidString:))
            if let matched = self.availableModels.first(where: { $0.modelID == model.modelID && ($0.endpointID == epUUID || epUUID == nil) }) {
                self.selectedModel = matched
            } else if let epUUID {
                self.selectedModel = NewsChatModelOption(endpointID: epUUID, endpointName: "Gateway", modelID: model.modelID)
            }
            var cfg = botStore.config(for: .readingCompanion)
            cfg.endpointID = epUUID
            cfg.modelOverride = model.modelID
            botStore.updateConfig(cfg, for: .readingCompanion)
            _ = try? PiKernelManager.shared.syncWorkspace()
        }
        cb.onSelectEffort = { raw in
            switch raw {
                case "simple": self.reasoningEffort = .simple
                case "deep": self.reasoningEffort = .deep
                default: self.reasoningEffort = .balanced
            }
        }
        cb.onInsertToEditor = { text in
            CotAgentCoordinator.shared.insertTextIntoActiveEditor(text)
        }
        cb.onOpenNewDocument = { text in
            let title = String(item.title.prefix(24))
            let docContent = "# \(item.title)\n\n> [原文链接](\(item.urlString))\n\n\(text)"
            if let handler = self.onOpenExcerptDocument {
                handler(title, docContent)
            } else {
                CotAgentCoordinator.shared.openNewMarkdownDocument(title: title, content: docContent, splitRight: true)
            }
        }
        cb.onOpenSettings = { target in
            if target == "ai" {
                (NSApp.delegate as? AppDelegate)?.showAIPreferences(nil)
            } else {
                (NSApp.delegate as? AppDelegate)?.openBotSettings(selecting: .readingCompanion)
            }
        }
        return cb
    }
    
    
    private func unifiedModelOptions() -> [AgentModelOption] {
        var seen: Set<String> = []
        var list: [AgentModelOption] = []
        for item in self.availableModels {
            guard seen.insert(item.modelID).inserted else { continue }
            list.append(AgentModelOption(
                id: item.id,
                title: item.modelID,
                endpointID: item.endpointID,
                modelID: item.modelID
            ))
        }
        let openCode = AIBotStore.shared.openCodeGoSelectableModels()
        for modelID in openCode.models where seen.insert(modelID).inserted {
            list.append(AgentModelOption(
                endpointID: openCode.profile?.id,
                modelID: modelID
            ))
        }
        return list
    }
    
    
    private func reloadAvailableModels() {
        let models = AIHotNewsService.availableChatModels()
        self.availableModels = models
        self.cachedModelOptions = self.unifiedModelOptions()
        let botOverride = AIBotStore.shared.config(for: .readingCompanion)
            .modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !botOverride.isEmpty,
           let matched = models.first(where: { $0.modelID == botOverride })
        {
            self.selectedModel = matched
            return
        }
        if let current = self.selectedModel, models.contains(current) {
            return
        }
        self.selectedModel = models.first
    }
    
    
    private func syncSelectionSideEffects() {
        guard let item = self.selectedItem else { return }
        self.newsService.markRead(item)
        Task {
            await self.newsService.fetchArticleExcerptIfNeeded(for: item)
        }
    }
    
    
    fileprivate static func relativeTimeString(from date: Date) -> String {
        let interval = max(0, Date().timeIntervalSince(date))
        if interval < 3600 {
            let mins = max(1, Int(interval / 60))
            return "\(mins)m"
        }
        if interval < 86_400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        }
        let days = Int(interval / 86_400)
        return "\(days)d"
    }
}


// MARK: - Isolated Native Editorial Reader Pane

private struct NewsEditorialArticlePane: View, Equatable {
    
    let item: AIHotNewsItem
    let cover: NSImage?
    let blocks: [NewsArticleBlock]
    let isLoadingArticle: Bool
    let previousItem: AIHotNewsItem?
    let nextItem: AIHotNewsItem?
    let bodyFontSize: CGFloat
    let tokens: StudioColorTokens
    let bui: BeautifulUITokens
    let secondaryInk: Color
    let mutedInk: Color
    let onSelectItem: (String) -> Void
    let onQuoteToAI: (String) -> Void
    
    @State private var hoveredBlockIndex: Int? = nil
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.cover === rhs.cover
            && lhs.blocks == rhs.blocks
            && lhs.isLoadingArticle == rhs.isLoadingArticle
            && lhs.previousItem?.id == rhs.previousItem?.id
            && lhs.nextItem?.id == rhs.nextItem?.id
            && lhs.tokens.isDark == rhs.tokens.isDark
    }
    
    var body: some View {
        let publisher = self.item.displayPublisherLabel
        let summaryText = self.item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        return ScrollViewReader { readerProxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(self.item.resolvedCategory.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(self.bui.accentInk)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(self.bui.accent.opacity(0.12), in: Capsule())
                        
                        if !publisher.isEmpty {
                            Text(publisher)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(self.bui.ink2)
                        }
                        
                        if let date = self.item.publishedAt {
                            Text("·")
                                .foregroundStyle(self.bui.ink3)
                            Text(DashboardNewsCenterView.relativeTimeString(from: date))
                                .font(.system(size: 11.5, design: .monospaced).monospacedDigit())
                                .foregroundStyle(self.bui.ink3)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .id("article-top")
                    
                    Text(self.item.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(self.bui.ink)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if let cover = self.cover {
                        Image(nsImage: cover)
                            .resizable()
                            .interpolation(.medium)
                            .antialiased(true)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(self.bui.line, lineWidth: 0.8)
                            )
                    }
                    
                    if !self.blocks.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(self.blocks.enumerated()), id: \.offset) { idx, block in
                                self.articleBlockView(block, index: idx)
                            }
                        }
                    } else if !summaryText.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(summaryText)
                                .font(.system(size: self.bodyFontSize, weight: .regular))
                                .foregroundStyle(self.bui.ink.opacity(0.92))
                                .lineSpacing(8)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(self.bui.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            
                            if self.isLoadingArticle {
                                self.loadingPlaceholder
                            }
                        }
                    } else if self.isLoadingArticle {
                        self.loadingPlaceholder
                    } else if let url = self.item.url {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(spacing: 6) {
                                Text(AppLanguage.text("前往外部浏览器阅读完整原文", en: "Read Full Article in Browser"))
                                    .font(.system(size: 13, weight: .medium))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(self.bui.accentInk)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(self.bui.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                    
                    if self.previousItem != nil || self.nextItem != nil {
                        Rectangle()
                            .fill(self.bui.line)
                            .frame(height: 1)
                            .padding(.top, 8)
                        
                        HStack(spacing: 12) {
                            if let prev = self.previousItem {
                                self.neighborButton(prev, isNext: false) {
                                    self.onSelectItem(prev.id)
                                    readerProxy.scrollTo("article-top", anchor: .top)
                                }
                            } else {
                                Spacer(minLength: 0).frame(maxWidth: .infinity)
                            }
                            
                            if let next = self.nextItem {
                                self.neighborButton(next, isNext: true) {
                                    self.onSelectItem(next.id)
                                    readerProxy.scrollTo("article-top", anchor: .top)
                                }
                            } else {
                                Spacer(minLength: 0).frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 32)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(self.bui.surface)
            .onChange(of: self.item.id) { _, _ in
                self.hoveredBlockIndex = nil
                readerProxy.scrollTo("article-top", anchor: .top)
            }
        }
    }
    
    
    @ViewBuilder
    private func articleBlockView(_ block: NewsArticleBlock, index: Int) -> some View {
        let isHovered = (self.hoveredBlockIndex == index)
        switch block {
            case .heading(let level, let text):
                Text(text)
                    .font(.system(size: self.bodyFontSize + (level <= 2 ? 2.5 : 1.0), weight: .semibold))
                    .foregroundStyle(self.bui.ink)
                    .padding(.top, 6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
            case .paragraph(let text):
                ZStack(alignment: .topTrailing) {
                    Text(text)
                        .font(.system(size: self.bodyFontSize, weight: .regular))
                        .foregroundStyle(self.bui.ink.opacity(0.90))
                        .lineSpacing(8)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isHovered ? self.bui.inset.opacity(0.75) : Color.clear)
                        )
                    
                    if isHovered && text.count >= 12 {
                        self.quoteToAIButton(text: text)
                            .padding(.top, 4)
                            .padding(.trailing, 6)
                    }
                }
                .padding(.horizontal, -8)
                .onHover { hovering in
                    self.hoveredBlockIndex = hovering ? index : (self.hoveredBlockIndex == index ? nil : self.hoveredBlockIndex)
                }
                
            case .quote(let text):
                ZStack(alignment: .topTrailing) {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(self.bui.accent)
                            .frame(width: 3)
                        
                        Text(text)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(self.bui.ink2)
                            .lineSpacing(6.5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(self.bui.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    
                    if isHovered && text.count >= 12 {
                        self.quoteToAIButton(text: text)
                            .padding(.top, 8)
                            .padding(.trailing, 8)
                    }
                }
                .onHover { hovering in
                    self.hoveredBlockIndex = hovering ? index : (self.hoveredBlockIndex == index ? nil : self.hoveredBlockIndex)
                }
                
            case .code(let code):
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(self.bui.ink)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(self.bui.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(self.bui.line, lineWidth: 0.8)
                )
                
            case .list(let items):
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(self.bui.ink3)
                                .frame(width: 4.5, height: 4.5)
                                .padding(.top, 8)
                            
                            Text(line)
                                .font(.system(size: self.bodyFontSize, weight: .regular))
                                .foregroundStyle(self.bui.ink.opacity(0.90))
                                .lineSpacing(7)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.leading, 4)
        }
    }
    
    
    private func quoteToAIButton(text: String) -> some View {
        Button {
            self.onQuoteToAI(text)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "text.quote")
                    .font(.system(size: 10, weight: .semibold))
                Text(AppLanguage.text("问 AI", en: "Ask AI"))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(self.bui.accentInk)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(self.bui.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(self.bui.lineStrong, lineWidth: 0.8))
            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .transition(.opacity)
    }
    
    
    private var loadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(self.tokens.inset)
                .frame(maxWidth: .infinity)
                .frame(height: 12)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(self.tokens.inset)
                .frame(maxWidth: .infinity)
                .frame(height: 12)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(self.tokens.inset)
                .frame(width: 220, height: 12)
        }
        .padding(.vertical, 4)
    }
    
    
    private func neighborButton(_ item: AIHotNewsItem, isNext: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if !isNext {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.mutedInk)
                }
                
                Text(item.title)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(self.secondaryInk)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: isNext ? .trailing : .leading)
                
                if isNext {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.mutedInk)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
}


// MARK: - LeiBox Reasoning Effort Slider (leibox.pantoria.cn/docs/animations/reasoning-effort-slider)

/// Faithful three-stop thinking slider (`Simple -> Balanced -> Deep`) with:
/// - Flowing star field drifting across the glowing active track
/// - Velocity-driven jelly stretch/squash deformation on drag & tap
/// - Soft spring snapping to the three discrete effort stops
struct LeiBoxReasoningEffortSlider: View {
    
    @Binding var effort: NewsReasoningEffort
    let accent: Color
    let isDark: Bool
    
    @State private var normalizedProgress: CGFloat = 0.5
    @State private var isDragging = false
    @State private var jellyVelocity: CGFloat = 0
    @State private var lastDragX: CGFloat?
    @State private var activityGate = AppActivityRenderGate.shared
    @State private var isWindowVisible = true
    
    private struct StarSeed {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let speed: CGFloat
        let phase: Double
    }
    
    private static let stars: [StarSeed] = (0..<22).map { i in
        let s = Double(i + 1)
        let fx = CGFloat((sin(s * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1.0))
        let fy = CGFloat((sin(s * 78.233) * 24634.6345).truncatingRemainder(dividingBy: 1.0))
        return StarSeed(
            x: abs(fx),
            y: 0.16 + abs(fy) * 0.68,
            size: (i % 3 == 0) ? 2.2 : 1.4,
            speed: 0.08 + CGFloat(i % 5) * 0.035,
            phase: s * 1.7
        )
    }
    
    
    var body: some View {
        let trackBg = self.isDark ? Color.white.opacity(0.10) : Color(red: 0.922, green: 0.929, blue: 0.945)
        let stretch = min(0.24, abs(self.jellyVelocity) * 0.012)
        let scaleX: CGFloat = 1.0 + stretch
        let scaleY: CGFloat = max(0.82, 1.0 - stretch * 0.50)
        
        VStack(spacing: 8) {
            GeometryReader { geo in
                let w = max(140, geo.size.width)
                let h: CGFloat = 26
                let knobD: CGFloat = 22
                let pad: CGFloat = (h - knobD) * 0.5
                let travelW = max(1, w - pad * 2 - knobD)
                let clampedP = max(0, min(1, self.normalizedProgress))
                let knobX = pad + clampedP * travelW
                let fillWidth = max(h, knobX + knobD + pad)
                
                ZStack(alignment: .leading) {
                    // Soft cool-gray recessed capsule track
                    Capsule()
                        .fill(trackBg)
                    
                    // Subtle right-end stop dot (exact detail from Deep Agent Composer)
                    HStack {
                        Spacer()
                        Circle()
                            .fill(self.isDark ? Color.white.opacity(0.24) : Color.black.opacity(0.18))
                            .frame(width: 3.5, height: 3.5)
                            .padding(.trailing, 11)
                    }
                    .allowsHitTesting(false)
                    
                    // Deep-night -> celestial-blue flowing star field active fill
                    let starfieldPaused = AnimationConstants.isReducedMotionEnabled
                        || !self.activityGate.isAppActive
                        || !self.isWindowVisible
                    TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: starfieldPaused)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let speedBoost: CGFloat = CGFloat(1 + self.effort.rawValue) * 0.55
                        Canvas(opaque: false, rendersAsynchronously: true) { ctx, size in
                            let activeRect = CGRect(x: 0, y: 0, width: min(size.width, fillWidth), height: size.height)
                            let activePath = Capsule().path(in: activeRect)
                            ctx.fill(
                                activePath,
                                with: .linearGradient(
                                    Gradient(colors: [
                                        Color(red: 0.08, green: 0.11, blue: 0.18),
                                        Color(red: 0.24, green: 0.37, blue: 0.67),
                                        Color(red: 0.52, green: 0.66, blue: 0.96),
                                    ]),
                                    startPoint: .zero,
                                    endPoint: CGPoint(x: max(28, activeRect.width), y: 0)
                                )
                            )
                            
                            ctx.drawLayer { layer in
                                layer.clip(to: activePath)
                                for star in Self.stars {
                                    let drift = (star.x + CGFloat(t) * star.speed * speedBoost).truncatingRemainder(dividingBy: 1.0)
                                    let sx = drift * size.width
                                    let sy = star.y * size.height
                                    let twinkle = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * 2.8 + star.phase))
                                    let r = star.size * 0.5
                                    layer.fill(
                                        Circle().path(in: CGRect(x: sx - r, y: sy - r, width: star.size, height: star.size)),
                                        with: .color(Color.white.opacity(twinkle * 0.92))
                                    )
                                }
                            }
                        }
                    }
                    .clipShape(Capsule())
                    .allowsHitTesting(false)
                    
                    // Crisp white circular jelly thumb knob with periwinkle luminous halo
                    Circle()
                        .fill(Color.white)
                        .overlay(
                            Circle()
                                .strokeBorder(Color(red: 0.45, green: 0.56, blue: 0.94).opacity(0.65), lineWidth: 1.4)
                        )
                        .shadow(color: Color(red: 0.26, green: 0.40, blue: 0.85).opacity(0.32), radius: self.isDragging ? 6 : 3.5, y: 1)
                        .frame(width: knobD, height: knobD)
                        .scaleEffect(x: scaleX, y: scaleY, anchor: .center)
                        .offset(x: knobX)
                        .allowsHitTesting(false)
                    
                    // Direct tap targets along the track
                    HStack(spacing: 0) {
                        ForEach(NewsReasoningEffort.allCases) { stop in
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    self.snap(to: stop, impulse: stop.rawValue > self.effort.rawValue ? 13 : -13)
                                }
                        }
                    }
                }
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            self.isDragging = true
                            let rawP = (value.location.x - pad - knobD * 0.5) / travelW
                            let clamped = max(0, min(1, rawP))
                            if let prevX = self.lastDragX {
                                let vx = value.location.x - prevX
                                self.jellyVelocity = self.jellyVelocity * 0.55 + vx * 0.95
                            }
                            self.lastDragX = value.location.x
                            self.normalizedProgress = clamped
                            let nearestIdx = min(2, max(0, Int((clamped * 2.0).rounded())))
                            if let nextStop = NewsReasoningEffort(rawValue: nearestIdx), nextStop != self.effort {
                                self.effort = nextStop
                            }
                        }
                        .onEnded { value in
                            self.isDragging = false
                            self.lastDragX = nil
                            let rawP = (value.location.x - pad - knobD * 0.5) / travelW
                            let clamped = max(0, min(1, rawP))
                            let nearestIdx = min(2, max(0, Int((clamped * 2.0).rounded())))
                            let stop = NewsReasoningEffort(rawValue: nearestIdx) ?? .balanced
                            self.snap(to: stop, impulse: 0)
                        }
                )
                .pointerStyle(.link)
            }
            .frame(height: 26)
            
            // Spacious unclipped 3-stop labels matching Deep Agent Composer (`简单 / 中度 / 深度`)
            HStack {
                ForEach(NewsReasoningEffort.allCases) { stop in
                    let active = (self.effort == stop)
                    let align: Alignment = stop == .simple ? .leading : (stop == .deep ? .trailing : .center)
                    Button {
                        self.snap(to: stop, impulse: stop.rawValue > self.effort.rawValue ? 13 : -13)
                    } label: {
                        Text(stop.title)
                            .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                            .foregroundStyle(
                                active
                                    ? Color(red: 0.22, green: 0.38, blue: 0.86)
                                    : (self.isDark ? Color.white.opacity(0.55) : Color.black.opacity(0.48))
                            )
                            .frame(maxWidth: .infinity, alignment: align)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(.horizontal, 2)
        }
        .observeWindowRenderActivity(self.$isWindowVisible)
        .onAppear {
            self.normalizedProgress = CGFloat(self.effort.rawValue) * 0.5
        }
        .onChange(of: self.effort) { _, next in
            if !self.isDragging {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                    self.normalizedProgress = CGFloat(next.rawValue) * 0.5
                }
            }
        }
    }
    
    
    private func snap(to stop: NewsReasoningEffort, impulse: CGFloat) {
        self.effort = stop
        withAnimation(.spring(response: 0.24, dampingFraction: 0.58)) {
            self.jellyVelocity = impulse
            self.normalizedProgress = CGFloat(stop.rawValue) * 0.5
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.36, dampingFraction: 0.62)) {
                self.jellyVelocity = 0
            }
        }
    }
}


// MARK: - Rich Markdown Parser & Renderer for AI Chat Replies

nonisolated enum NewsMarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulletList([String])
    case orderedList([(number: String, text: String)])
    case blockquote(String)
    case codeBlock(language: String, code: String)
    case table(headers: [String], rows: [[String]])
    case divider
    
    static func == (lhs: NewsMarkdownBlock, rhs: NewsMarkdownBlock) -> Bool {
        switch (lhs, rhs) {
            case (.heading(let l1, let t1), .heading(let l2, let t2)): l1 == l2 && t1 == t2
            case (.paragraph(let a), .paragraph(let b)): a == b
            case (.bulletList(let a), .bulletList(let b)): a == b
            case (.orderedList(let a), .orderedList(let b)):
                a.count == b.count && zip(a, b).allSatisfy { $0.number == $1.number && $0.text == $1.text }
            case (.blockquote(let a), .blockquote(let b)): a == b
            case (.codeBlock(let l1, let c1), .codeBlock(let l2, let c2)): l1 == l2 && c1 == c2
            case (.table(let h1, let r1), .table(let h2, let r2)): h1 == h2 && r1 == r2
            case (.divider, .divider): true
            default: false
        }
    }
}


nonisolated enum NewsMarkdownParser {
    
    static func parse(_ source: String) -> [NewsMarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var blocks: [NewsMarkdownBlock] = []
        var idx = 0
        
        while idx < lines.count {
            let raw = lines[idx]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            
            if trimmed.isEmpty {
                idx += 1
                continue
            }
            
            // Fenced code block (gracefully handles unclosed fence while streaming!)
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                idx += 1
                var codeLines: [String] = []
                while idx < lines.count {
                    if lines[idx].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        idx += 1
                        break
                    }
                    codeLines.append(lines[idx])
                    idx += 1
                }
                blocks.append(.codeBlock(language: lang, code: codeLines.joined(separator: "\n")))
                continue
            }
            
            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.divider)
                idx += 1
                continue
            }
            
            // Heading (# to ####)
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" })
                if hashes.count >= 1, hashes.count <= 4 {
                    let after = trimmed.dropFirst(hashes.count)
                    if after.first == " " || after.isEmpty {
                        let title = after.trimmingCharacters(in: .whitespaces)
                        if !title.isEmpty {
                            blocks.append(.heading(level: hashes.count, text: title))
                            idx += 1
                            continue
                        }
                    }
                }
            }
            
            // Markdown Table (| H1 | H2 | followed by | --- | --- |)
            if trimmed.contains("|"), idx + 1 < lines.count {
                let nextTrim = lines[idx + 1].trimmingCharacters(in: .whitespaces)
                if Self.isTableSeparator(nextTrim) {
                    let headers = Self.splitTableRow(trimmed)
                    idx += 2
                    var rows: [[String]] = []
                    while idx < lines.count {
                        let rTrim = lines[idx].trimmingCharacters(in: .whitespaces)
                        guard !rTrim.isEmpty, rTrim.contains("|") else { break }
                        rows.append(Self.splitTableRow(rTrim))
                        idx += 1
                    }
                    if !headers.isEmpty {
                        blocks.append(.table(headers: headers, rows: rows))
                        continue
                    }
                }
            }
            
            // Blockquote
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while idx < lines.count {
                    let qTrim = lines[idx].trimmingCharacters(in: .whitespaces)
                    guard qTrim.hasPrefix(">") else { break }
                    let body = String(qTrim.dropFirst()).trimmingCharacters(in: .whitespaces)
                    if !body.isEmpty { quoteLines.append(body) }
                    idx += 1
                }
                if !quoteLines.isEmpty {
                    blocks.append(.blockquote(quoteLines.joined(separator: "\n")))
                }
                continue
            }
            
            // Unordered bullet list
            if Self.bulletItemText(from: trimmed) != nil {
                var items: [String] = []
                while idx < lines.count {
                    let lTrim = lines[idx].trimmingCharacters(in: .whitespaces)
                    if let text = Self.bulletItemText(from: lTrim) {
                        items.append(text)
                        idx += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bulletList(items))
                continue
            }
            
            // Ordered numbered list
            if Self.orderedItem(from: trimmed) != nil {
                var items: [(number: String, text: String)] = []
                while idx < lines.count {
                    let lTrim = lines[idx].trimmingCharacters(in: .whitespaces)
                    if let item = Self.orderedItem(from: lTrim) {
                        items.append(item)
                        idx += 1
                    } else {
                        break
                    }
                }
                blocks.append(.orderedList(items))
                continue
            }
            
            // Paragraph (merge contiguous plain lines)
            var paraLines: [String] = [trimmed]
            idx += 1
            while idx < lines.count {
                let nextTrim = lines[idx].trimmingCharacters(in: .whitespaces)
                if nextTrim.isEmpty
                    || nextTrim.hasPrefix("#")
                    || nextTrim.hasPrefix("```")
                    || nextTrim.hasPrefix(">")
                    || nextTrim == "---"
                    || nextTrim == "***"
                    || Self.bulletItemText(from: nextTrim) != nil
                    || Self.orderedItem(from: nextTrim) != nil
                    || (nextTrim.contains("|") && idx + 1 < lines.count && Self.isTableSeparator(lines[idx + 1].trimmingCharacters(in: .whitespaces)))
                {
                    break
                }
                paraLines.append(nextTrim)
                idx += 1
            }
            blocks.append(.paragraph(paraLines.joined(separator: "\n")))
        }
        
        return blocks
    }
    
    
    private static func bulletItemText(from trimmed: String) -> String? {
        for prefix in ["- ", "* ", "• "] where trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
    
    
    private static func orderedItem(from trimmed: String) -> (number: String, text: String)? {
        guard let dotIdx = trimmed.firstIndex(of: ".") else { return nil }
        let numPart = String(trimmed[..<dotIdx])
        guard !numPart.isEmpty, numPart.count <= 3, numPart.allSatisfy(\.isNumber) else { return nil }
        let afterDot = trimmed.index(after: dotIdx)
        guard afterDot < trimmed.endIndex, trimmed[afterDot] == " " else { return nil }
        let text = String(trimmed[trimmed.index(after: afterDot)...]).trimmingCharacters(in: .whitespaces)
        return (numPart, text)
    }
    
    
    private static func isTableSeparator(_ trimmed: String) -> Bool {
        guard trimmed.contains("|"), trimmed.contains("-") else { return false }
        let allowed = CharacterSet(charactersIn: "|-: ")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
    
    
    private static func splitTableRow(_ trimmed: String) -> [String] {
        var row = trimmed
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|") { row.removeLast() }
        return row.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}


struct NewsMarkdownContentView: View {
    
    let markdown: String
    let isStreaming: Bool
    let tokens: StudioColorTokens
    let secondaryInk: Color
    let mutedInk: Color
    
    @State private var copiedCodeKey: String?
    
    
    var body: some View {
        let blocks = MarkdownRenderCache.blocks(for: self.markdown)
        
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                let key = "md-\(idx)"
                NewsMarkdownBlockRow(
                    block: block,
                    tokens: self.tokens,
                    secondaryInk: self.secondaryInk,
                    mutedInk: self.mutedInk,
                    isCopied: self.copiedCodeKey == key,
                    onCopyCode: { code in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                        self.copiedCodeKey = key
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.5))
                            if self.copiedCodeKey == key { self.copiedCodeKey = nil }
                        }
                    }
                )
                .equatable()
            }
            
            if self.isStreaming {
                TypewriterStreamingCursor(accent: self.tokens.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


private struct NewsMarkdownBlockRow: View, Equatable {
    
    let block: NewsMarkdownBlock
    let tokens: StudioColorTokens
    let secondaryInk: Color
    let mutedInk: Color
    let isCopied: Bool
    let onCopyCode: (String) -> Void
    
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.block == rhs.block && lhs.tokens == rhs.tokens && lhs.isCopied == rhs.isCopied
    }
    
    
    var body: some View {
        switch self.block {
            case .heading(let level, let text):
                self.inlineMarkdownText(text)
                    .font(.system(size: level == 1 ? 16 : (level == 2 ? 14.5 : 13.5), weight: .semibold))
                    .foregroundStyle(self.tokens.primaryInk)
                    .padding(.top, level <= 2 ? 4 : 2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
            case .paragraph(let text):
                self.inlineMarkdownText(text)
                    .font(.system(size: 13.2, weight: .regular))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.92))
                    .lineSpacing(5.5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
            case .bulletList(let items):
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(self.tokens.accent.opacity(0.80))
                                .frame(width: 4.5, height: 4.5)
                                .padding(.top, 6.5)
                            
                            self.inlineMarkdownText(item)
                                .font(.system(size: 13.2, weight: .regular))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.92))
                                .lineSpacing(5)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.leading, 2)
                
            case .orderedList(let items):
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 7) {
                            Text("\(item.number).")
                                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.tokens.accentText)
                                .frame(minWidth: 18, alignment: .trailing)
                                .padding(.top, 1)
                            
                            self.inlineMarkdownText(item.text)
                                .font(.system(size: 13.2, weight: .regular))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.92))
                                .lineSpacing(5)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                
            case .blockquote(let text):
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(self.tokens.accent)
                        .frame(width: 3)
                    
                    self.inlineMarkdownText(text)
                        .font(.system(size: 12.8, weight: .regular))
                        .foregroundStyle(self.secondaryInk)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                
            case .codeBlock(let language, let code):
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(language.isEmpty ? "code" : language)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(self.mutedInk)
                        
                        Spacer()
                        
                        Button {
                            self.onCopyCode(code)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: self.isCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 9.5, weight: .semibold))
                                Text(self.isCopied ? AppLanguage.text("已复制", en: "Copied") : AppLanguage.text("复制代码", en: "Copy"))
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundStyle(self.isCopied ? self.tokens.accentText : self.mutedInk)
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(self.tokens.insetHover)
                    
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(code)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(self.tokens.primaryInk)
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
                )
                
            case .table(let headers, let rows):
                let colCount = max(1, headers.count)
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(0..<colCount, id: \.self) { col in
                                self.inlineMarkdownText(headers[col])
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(self.tokens.primaryInk)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 7)
                                    .frame(minWidth: 84, maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .background(self.tokens.insetHover)
                        
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            Rectangle().fill(self.tokens.hairline).frame(height: 0.5)
                            HStack(spacing: 0) {
                                ForEach(0..<colCount, id: \.self) { col in
                                    let cell = col < row.count ? row[col] : ""
                                    self.inlineMarkdownText(cell)
                                        .font(.system(size: 11.8))
                                        .foregroundStyle(self.secondaryInk)
                                        .textSelection(.enabled)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 6)
                                        .frame(minWidth: 84, maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
                )
                
            case .divider:
                Rectangle()
                    .fill(self.tokens.hairline)
                    .frame(height: 0.8)
                    .padding(.vertical, 2)
        }
    }
    
    
    private func inlineMarkdownText(_ raw: String) -> Text {
        if let attr = MarkdownRenderCache.attributedInline(for: raw) {
            return Text(attr)
        }
        return Text(raw)
    }
}


/// Crisp pulsing streaming typewriter caret shown while AI is actively streaming characters.
private struct TypewriterStreamingCursor: View {
    
    let accent: Color
    @State private var pulse = false
    
    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(self.accent)
                .frame(width: 6, height: 13)
                .opacity(self.pulse ? 0.25 : 0.95)
                .animation(.easeInOut(duration: 0.52).repeatForever(autoreverses: true), value: self.pulse)
        }
        .onAppear {
            self.pulse = true
        }
    }
}


// MARK: - Xiaohongshu-Style Visual News Card

private struct XiaohongshuNewsCard: View, Equatable {
    
    let item: AIHotNewsItem
    let cover: NSImage?
    let coverHeight: CGFloat
    let isRead: Bool
    let hasAIBrief: Bool
    let tokens: StudioColorTokens
    let secondaryInk: Color
    let mutedInk: Color
    let onAppearLoadCover: () -> Void
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.item.title == rhs.item.title
            && lhs.cover === rhs.cover
            && abs(lhs.coverHeight - rhs.coverHeight) < 0.5
            && lhs.isRead == rhs.isRead
            && lhs.hasAIBrief == rhs.hasAIBrief
            && lhs.tokens.isDark == rhs.tokens.isDark
    }
    
    
    private var accentColor: Color {
        let seed = Int(DashboardNewsCenterView.stableSeed(for: self.item.id) % 4)
        return switch seed {
            case 0: self.tokens.accent
            case 1: self.tokens.secondaryAccent
            case 2: Color(red: 0.212, green: 0.478, blue: 0.612)
            default: self.tokens.heat3
        }
    }
    
    
    var body: some View {
        let publisher = self.item.displayPublisherLabel
        let sourceLabel = publisher.isEmpty ? self.item.resolvedCategory.label : publisher
        let initialChar = String(sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
        let summarySnippet = self.item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        Button(action: self.onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if let cover = self.cover {
                        Color.clear
                            .frame(height: self.coverHeight)
                            .overlay {
                                Image(nsImage: cover)
                                    .resizable()
                                    .interpolation(.medium)
                                    .antialiased(true)
                                    .scaledToFill()
                            }
                            .clipped()
                    } else {
                        self.editorialCoverTile(summarySnippet: summarySnippet)
                            .frame(height: self.coverHeight)
                    }
                    
                    HStack {
                        Text(self.item.resolvedCategory.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(self.tokens.primaryInk)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(self.tokens.card.opacity(0.90), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        
                        Spacer()
                        
                        if self.hasAIBrief {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(self.tokens.onAccentInk)
                                .frame(width: 20, height: 20)
                                .background(self.tokens.accent, in: Circle())
                        } else if !self.isRead {
                            Circle()
                                .fill(self.tokens.accent)
                                .frame(width: 7, height: 7)
                        }
                    }
                    .padding(9)
                }
                .frame(maxWidth: .infinity)
                .clipped()
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(self.item.title)
                        .font(.system(size: 13.5, weight: self.isRead ? .medium : .semibold))
                        .foregroundStyle(self.isRead ? self.secondaryInk : self.tokens.primaryInk)
                        .lineLimit(2)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    
                    Spacer(minLength: 4)
                    
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(self.accentColor.opacity(self.tokens.isDark ? 0.28 : 0.14))
                            Text(initialChar.isEmpty ? "N" : initialChar)
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(self.accentColor)
                        }
                        .frame(width: 18, height: 18)
                        
                        Text(sourceLabel)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(self.mutedInk)
                            .lineLimit(1)
                        
                        Spacer(minLength: 4)
                        
                        if let date = self.item.publishedAt {
                            Text(DashboardNewsCenterView.relativeTimeString(from: date))
                                .font(.system(size: 10.5, design: .monospaced).monospacedDigit())
                                .foregroundStyle(self.mutedInk)
                        }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
                .frame(height: 82, alignment: .topLeading)
            }
            .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        self.isHovered ? self.tokens.accent.opacity(0.48) : self.tokens.hairline,
                        lineWidth: 1.0
                    )
            )
            .shadow(color: self.tokens.cardShadow, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onAppear {
            self.onAppearLoadCover()
        }
        .onHover { hovering in
            if hovering != self.isHovered {
                self.isHovered = hovering
            }
        }
    }
    
    
    private func editorialCoverTile(summarySnippet: String) -> some View {
        let accent = self.accentColor
        let headline = summarySnippet.isEmpty ? self.item.title : summarySnippet
        return ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [accent.opacity(self.tokens.isDark ? 0.28 : 0.14), self.tokens.inset],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(alignment: .leading, spacing: 6) {
                Spacer(minLength: 24)
                
                Text("“")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(accent.opacity(0.36))
                    .frame(height: 18, alignment: .topLeading)
                
                Text(headline)
                    .font(.system(size: summarySnippet.isEmpty ? 14 : 12.5, weight: summarySnippet.isEmpty ? .semibold : .medium))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.84))
                    .lineLimit(5)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 10)
        }
    }
}


// MARK: - Gesture-Locked Single-Page Trackpad / Mouse-Wheel Pager

/// Non-hit-testing NSView that turns **strictly at most 1 page per trackpad swipe or discrete wheel step**
/// (ignoring post-turn trackpad momentum tails so one flick never overshoots multiple pages).
private final class NewsGridWheelPagerMonitorView: NSView {
    
    var onPageDelta: ((Int) -> Void)?
    private nonisolated(unsafe) var eventMonitor: Any?
    private var accumulatedDelta: CGFloat = 0
    private var consumedInCurrentGesture = false
    private var lastDiscreteTurnTime: TimeInterval = 0
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.teardownMonitor()
        guard self.window != nil else { return }
        
        self.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self,
                  let window = self.window,
                  event.window === window,
                  !self.isHiddenOrHasHiddenAncestor
            else { return event }
            
            let localPt = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(localPt) else { return event }
            
            // Trackpad gesture lifecycle: allow at most 1 page turn per physical two-finger touch
            if event.hasPreciseScrollingDeltas {
                if event.phase == .began {
                    self.accumulatedDelta = 0
                    self.consumedInCurrentGesture = false
                }
                if !event.momentumPhase.isEmpty {
                    return nil
                }
                if self.consumedInCurrentGesture {
                    return nil
                }
                let dominant = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
                    ? event.scrollingDeltaX
                    : event.scrollingDeltaY
                self.accumulatedDelta += dominant
                let threshold: CGFloat = 38.0
                if abs(self.accumulatedDelta) >= threshold {
                    let pageStep = self.accumulatedDelta < 0 ? 1 : -1
                    self.consumedInCurrentGesture = true
                    self.accumulatedDelta = 0
                    self.onPageDelta?(pageStep)
                }
                if event.phase == .ended || event.phase == .cancelled {
                    self.accumulatedDelta = 0
                }
                return nil
            } else {
                // Discrete notched mouse wheel
                let now = ProcessInfo.processInfo.systemUptime
                guard now - self.lastDiscreteTurnTime >= 0.24 else { return nil }
                let raw = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
                    ? event.scrollingDeltaY
                    : event.scrollingDeltaX
                guard abs(raw) > 0.05 else { return event }
                self.lastDiscreteTurnTime = now
                self.onPageDelta?(raw < 0 ? 1 : -1)
                return nil
            }
        }
    }
    
    private func teardownMonitor() {
        if let monitor = self.eventMonitor {
            NSEvent.removeMonitor(monitor)
            self.eventMonitor = nil
        }
    }
    
    deinit {
        if let monitor = self.eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}


private struct NewsGridWheelPagerRepresentable: NSViewRepresentable {
    
    let onPageDelta: (Int) -> Void
    
    func makeNSView(context: Context) -> NewsGridWheelPagerMonitorView {
        let v = NewsGridWheelPagerMonitorView()
        v.onPageDelta = self.onPageDelta
        return v
    }
    
    func updateNSView(_ nsView: NewsGridWheelPagerMonitorView, context: Context) {
        nsView.onPageDelta = self.onPageDelta
    }
}
