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

/// Editorial magazine visual NEWS workspace with Douyin/Xiaohongshu-style fresh-batch refresh,
/// full-text search, persistent browsing history, reliable article extraction, and fast-summarizing NEWS AI companion.
struct DashboardNewsCenterView: View {
    
    @Bindable var newsService: AIHotNewsService
    let tokens: StudioColorTokens
    var surfaceColor: Color? = nil
    let initialSelectedID: String?
    var isEmbeddedInPane: Bool = false
    var initialCategory: NewsFeedCategory? = nil
    var initialSearchQuery: String? = nil
    var hasCustomBackground: Bool = false
    let onClose: () -> Void
    var onOpenExcerptDocument: ((String, String) -> Void)?
    
    @State private var selectedCategory: NewsFeedCategory
    @State private var searchText: String
    @State private var selectedItemID: String?
    @State private var isShortFeedMode: Bool
    @State private var shortFeedIndex: Int = 0
    @State private var isSideAICollapsed: Bool = false
    @State private var shortFeedTransitionEdge: Edge = .bottom
    @State private var isHistoryPopoverPresented: Bool = false
    @State private var feedScrollResetToken: UInt64 = 0
    @FocusState private var isSearchFieldFocused: Bool
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
        surfaceColor: Color? = nil,
        initialSelectedID: String?,
        isEmbeddedInPane: Bool = false,
        initialCategory: NewsFeedCategory? = nil,
        initialSearchQuery: String? = nil,
        hasCustomBackground: Bool = false,
        onClose: @escaping () -> Void,
        onOpenExcerptDocument: ((String, String) -> Void)? = nil
    ) {
        self.newsService = newsService
        self.tokens = tokens
        self.surfaceColor = surfaceColor
        self.initialSelectedID = initialSelectedID
        self.isEmbeddedInPane = isEmbeddedInPane
        self.initialCategory = initialCategory
        self.initialSearchQuery = initialSearchQuery
        self.hasCustomBackground = hasCustomBackground
        self.onClose = onClose
        self.onOpenExcerptDocument = onOpenExcerptDocument
        self._selectedCategory = State(initialValue: initialCategory ?? newsService.selectedCategory)
        self._searchText = State(initialValue: initialSearchQuery ?? "")
        self._selectedItemID = State(initialValue: initialSelectedID)
        self._isShortFeedMode = State(initialValue: isEmbeddedInPane && initialSelectedID == nil)
    }
    
    private let bodyFontSize: CGFloat = 15.5
    
    private var canvasBackground: Color {
        self.surfaceColor ?? self.tokens.canvasTop
    }
    
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
    
    private func matchesSearch(_ item: AIHotNewsItem, query: String) -> Bool {
        if item.title.lowercased().contains(query)
            || item.displayPublisherLabel.lowercased().contains(query)
            || item.source.lowercased().contains(query)
            || (item.tag?.lowercased().contains(query) ?? false)
            || (item.summary?.lowercased().contains(query) ?? false)
        {
            return true
        }
        if let cachedBody = self.newsService.articleContents[item.id]?.markdownBody.lowercased(),
           cachedBody.contains(query)
        {
            return true
        }
        return false
    }
    
    private var displayedItems: [AIHotNewsItem] {
        let base = self.newsService.feedItems(for: self.selectedCategory)
        let query = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return base }
        return base.filter { self.matchesSearch($0, query: query) }
    }
    
    private var crossCategorySearchMatchCount: Int {
        let query = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty, self.selectedCategory != .all else { return 0 }
        return self.newsService.feedItems(for: .all).filter { self.matchesSearch($0, query: query) }.count
    }
    
    private var selectedItem: AIHotNewsItem? {
        guard let id = self.selectedItemID else { return nil }
        return self.displayedItems.first(where: { $0.id == id })
            ?? self.newsService.findItem(byID: id)
    }
    
    private var activeShortFeedItem: AIHotNewsItem? {
        let items = self.displayedItems
        guard !items.isEmpty else { return nil }
        let idx = min(max(0, self.shortFeedIndex), items.count - 1)
        return items[idx]
    }
    
    private var activeCompanionItemID: String? {
        self.selectedItem?.id ?? (self.isShortFeedMode ? self.activeShortFeedItem?.id : nil)
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
            } else if self.isShortFeedMode {
                self.shortVideoFeedWithCompanionStage
                    .transition(.opacity)
            } else {
                self.editorialFeedStage
                    .transition(.opacity)
            }
        }
        .background(alignment: .topLeading) {
            Button("") {
                if self.selectedItemID == nil {
                    self.isSearchFieldFocused = true
                }
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0.001)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(self.hasCustomBackground ? Color.clear : self.canvasBackground)
        .onAppear {
            self.reloadAvailableModels()
            self.syncSelectionSideEffects()
            self.syncShortFeedStorySideEffects()
            if self.newsChatStreamListenerID == nil {
                let webCtrl = self.newsChatWebController
                self.newsChatStreamListenerID = self.newsService.addChatStreamPatchListener { itemID, patch in
                    if (self.selectedItemID ?? self.activeCompanionItemID) == itemID {
                        webCtrl.pushStreamPatch(patch)
                    }
                }
            }
            Task {
                await self.newsService.refreshIfNeeded()
                self.syncShortFeedStorySideEffects()
            }
        }
        .onDisappear {
            if let id = self.newsChatStreamListenerID {
                self.newsService.removeChatStreamPatchListener(id)
                self.newsChatStreamListenerID = nil
            }
        }
        .onChange(of: self.selectedCategory) { _, _ in
            self.shortFeedIndex = 0
            self.feedScrollResetToken &+= 1
            self.syncShortFeedStorySideEffects()
        }
        .onChange(of: self.shortFeedIndex) { _, _ in
            self.newsQuotedExcerpt = nil
            self.syncShortFeedStorySideEffects()
        }
        .onChange(of: self.searchText) { _, _ in
            self.shortFeedIndex = 0
        }
        .onKeyPress(.upArrow) {
            guard self.selectedItemID == nil, self.isShortFeedMode, !self.isSearchFieldFocused else { return .ignored }
            self.stepShortFeed(delta: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard self.selectedItemID == nil, self.isShortFeedMode, !self.isSearchFieldFocused else { return .ignored }
            self.stepShortFeed(delta: 1)
            return .handled
        }
        .onChange(of: self.selectedItemID) { _, _ in
            self.isModelPopoverOpen = false
            self.isHistoryPopoverPresented = false
            self.newsQuotedExcerpt = nil
            self.reloadAvailableModels()
            self.syncSelectionSideEffects()
        }
        .onKeyPress(.escape) {
            if self.isHistoryPopoverPresented {
                self.isHistoryPopoverPresented = false
                return .handled
            }
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
            if !self.searchText.isEmpty {
                self.searchText = ""
                return .handled
            }
            self.onClose()
            return .handled
        }
    }
    
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack(spacing: 10) {
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
                            self.newsService.prefetchCovers(for: category, limit: 16)
                            if self.newsService.feedItems(for: category).isEmpty {
                                Task {
                                    await self.newsService.refreshFeed(for: category, visibleCount: 12, forceNetwork: true)
                                }
                            }
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
                // Upgraded Search Bar with match count & clear button
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(self.mutedInk)
                    TextField(AppLanguage.text("搜索标题、来源或正文 (⌘F)", en: "Search news (⌘F)"), text: self.$searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(self.tokens.primaryInk)
                        .focused(self.$isSearchFieldFocused)
                        .frame(minWidth: 140, maxWidth: 220)
                    if !self.searchText.isEmpty {
                        Text("\(self.displayedItems.count)")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced).monospacedDigit())
                            .foregroundStyle(self.mutedInk)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(self.tokens.inset, in: Capsule())
                        
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
                        .strokeBorder(self.isSearchFieldFocused ? self.tokens.accent.opacity(0.6) : self.tokens.hairline, lineWidth: 0.8)
                )
                
                // Browsing History Popover Button
                Button {
                    self.isHistoryPopoverPresented.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11.5, weight: .medium))
                        Text(AppLanguage.text("历史", en: "History"))
                            .font(.system(size: 12, weight: .medium))
                        if !self.newsService.browsingHistory.isEmpty {
                            Text("\(min(99, self.newsService.browsingHistory.count))")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced).monospacedDigit())
                                .foregroundStyle(self.tokens.accent)
                        }
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
                .popover(isPresented: self.$isHistoryPopoverPresented, arrowEdge: .bottom) {
                    self.browsingHistoryPopover
                }
                
                // Short-Video Reel vs Grid Mode Switcher
                HStack(spacing: 2) {
                    Button {
                        withAnimation(DashMotion.quick) {
                            self.isShortFeedMode = true
                        }
                        self.syncShortFeedStorySideEffects()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 10.5))
                            Text(AppLanguage.text("刷读", en: "Reel"))
                                .font(.system(size: 11.5, weight: self.isShortFeedMode ? .semibold : .regular))
                        }
                        .foregroundStyle(self.isShortFeedMode ? self.tokens.onAccentInk : self.secondaryInk)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(self.isShortFeedMode ? self.tokens.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    Button {
                        withAnimation(DashMotion.quick) {
                            self.isShortFeedMode = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 10.5))
                            Text(AppLanguage.text("网格", en: "Grid"))
                                .font(.system(size: 11.5, weight: !self.isShortFeedMode ? .semibold : .regular))
                        }
                        .foregroundStyle(!self.isShortFeedMode ? self.tokens.onAccentInk : self.secondaryInk)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(!self.isShortFeedMode ? self.tokens.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                .padding(3)
                .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(self.tokens.hairline, lineWidth: 0.8))
                
                // Douyin / Xiaohongshu-style Feed Refresh Pill
                Button {
                    self.triggerFeedRefresh()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: self.newsService.isLoading ? "hourglass" : "arrow.clockwise")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(AppLanguage.text("换一批", en: "Refresh"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(self.tokens.onAccentInk)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(self.tokens.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(self.newsService.isLoading)
                .pointerStyle(.link)
                .help(AppLanguage.text("刷新换一批新资讯", en: "Refresh with new items"))
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
                        self.newsService.toggleBookmark(item)
                    } label: {
                        Image(systemName: self.newsService.isBookmarked(item) ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(self.newsService.isBookmarked(item) ? self.tokens.accent : self.secondaryInk)
                            .frame(width: 30, height: 30)
                            .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(AppLanguage.text("收藏", en: "Bookmark"))
                    
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
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 11.5, weight: .medium))
                            Text(AppLanguage.text("转交总管", en: "Ask Butler"))
                                .font(.system(size: 12.5, weight: .medium))
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
                
                Button {
                    if let item = self.selectedItem {
                        Task {
                            await self.newsService.refetchArticleExcerpt(for: item)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
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
                .pointerStyle(.link)
                .help(AppLanguage.text("重新抓取原文正文", en: "Refetch article text"))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
    }
    
    
    // MARK: - Browsing History Popover
    
    private var browsingHistoryPopover: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(self.tokens.accent)
                    Text(AppLanguage.text("浏览历史", en: "Browsing History"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(self.tokens.primaryInk)
                }
                Spacer()
                if !self.newsService.browsingHistory.isEmpty {
                    Button {
                        self.newsService.clearBrowsingHistory()
                    } label: {
                        Text(AppLanguage.text("清空", en: "Clear"))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(self.mutedInk)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            
            Rectangle()
                .fill(self.tokens.hairline)
                .frame(height: 0.75)
            
            if self.newsService.browsingHistory.isEmpty {
                VStack(spacing: 6) {
                    Text(AppLanguage.text("暂无浏览记录", en: "No browsing history"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(self.mutedInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(self.newsService.browsingHistory.enumerated()), id: \.element.id) { idx, entry in
                            if idx > 0 {
                                Rectangle()
                                    .fill(self.tokens.hairline.opacity(0.65))
                                    .frame(height: 0.65)
                                    .padding(.horizontal, 14)
                            }
                            HStack(alignment: .top, spacing: 8) {
                                Button {
                                    self.isHistoryPopoverPresented = false
                                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                                        self.selectedItemID = entry.item.id
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.item.title)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(self.tokens.primaryInk)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        
                                        HStack(spacing: 6) {
                                            Text(entry.item.resolvedCategory == .xSocial ? "X" : entry.item.resolvedCategory.badgeLabel)
                                                .font(.system(size: 9.5, weight: .semibold))
                                                .foregroundStyle(self.tokens.accent)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(self.tokens.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                            
                                            let pub = entry.item.displayPublisherLabel
                                            if !pub.isEmpty {
                                                Text(pub)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(self.mutedInk)
                                                    .lineLimit(1)
                                            }
                                            
                                            Spacer(minLength: 4)
                                            
                                            Text(Self.relativeTimeString(from: entry.visitedAt))
                                                .font(.system(size: 10.5, design: .monospaced).monospacedDigit())
                                                .foregroundStyle(self.mutedInk)
                                            
                                            if entry.visitCount > 1 {
                                                Text("· \(entry.visitCount)次")
                                                    .font(.system(size: 10).monospacedDigit())
                                                    .foregroundStyle(self.mutedInk.opacity(0.8))
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                                
                                Button {
                                    self.newsService.removeBrowsingHistory(id: entry.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(self.mutedInk)
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
        }
        .frame(width: 360, height: 420)
        .background(self.tokens.card)
    }
    
    
    // MARK: - Douyin / Xiaohongshu-Style Editorial Feed (Zero Pagination)
    
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
    
    private func triggerFeedRefresh() {
        self.shortFeedIndex = 0
        self.feedScrollResetToken &+= 1
        Task {
            await self.newsService.refreshFeed(
                for: self.selectedCategory,
                visibleCount: 10,
                forceNetwork: true
            )
            self.syncShortFeedStorySideEffects()
        }
    }
    
    
    // MARK: - Douyin / Short-Video Feed + Always-On Side AI Reading Companion
    
    private func stepShortFeed(delta: Int) {
        let items = self.displayedItems
        guard !items.isEmpty else { return }
        let clampedCurrent = min(max(0, self.shortFeedIndex), items.count - 1)
        let next = clampedCurrent + delta
        if next >= items.count {
            self.shortFeedTransitionEdge = .bottom
            self.triggerFeedRefresh()
            return
        }
        guard next >= 0 else { return }
        self.shortFeedTransitionEdge = delta > 0 ? .bottom : .top
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) {
            self.shortFeedIndex = next
        }
    }
    
    
    private func syncShortFeedStorySideEffects() {
        guard self.selectedItemID == nil, self.isShortFeedMode else { return }
        let items = self.displayedItems
        guard !items.isEmpty else { return }
        let idx = min(max(0, self.shortFeedIndex), items.count - 1)
        let active = items[idx]
        self.newsService.recordBrowsingHistory(active)
        self.newsService.requestCoverLoad(for: active)
        Task {
            await self.newsService.fetchArticleExcerptIfNeeded(for: active)
        }
        // Pre-warm next 2 cards in the feed so swiping is instantaneous
        for lookAhead in 1...2 where idx + lookAhead < items.count {
            let nextItem = items[idx + lookAhead]
            self.newsService.requestCoverLoad(for: nextItem)
            Task {
                await self.newsService.fetchArticleExcerptIfNeeded(for: nextItem)
            }
        }
    }
    
    
    private var shortVideoFeedWithCompanionStage: some View {
        let items = self.displayedItems
        let bui = BeautifulUITokens.resolve(isDark: self.tokens.isDark)
        
        return GeometryReader { geo in
            if let story = self.activeShortFeedItem {
                let idx = min(max(0, self.shortFeedIndex), max(0, items.count - 1))
                let isWide = geo.size.width >= 680
                let showCompanion = !self.isSideAICollapsed
                let chatWidth = isWide ? min(440, max(300, geo.size.width * self.chatWidthFraction)) : geo.size.width
                
                if isWide {
                    HStack(spacing: 0) {
                        self.shortVideoReelStage(story: story, index: idx, totalCount: items.count, bui: bui)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        if showCompanion {
                            self.newsSplitDivider(totalWidth: geo.size.width, bui: bui)
                            self.shortFeedCompanionPanel(for: story, bui: bui)
                                .frame(width: chatWidth)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .coordinateSpace(name: "newsSplitStage")
                } else {
                    VStack(spacing: 0) {
                        self.shortVideoReelStage(story: story, index: idx, totalCount: items.count, bui: bui)
                            .frame(height: showCompanion ? max(250, geo.size.height * 0.56) : geo.size.height)
                        
                        if showCompanion {
                            Rectangle().fill(bui.line).frame(height: 1)
                            self.shortFeedCompanionPanel(for: story, bui: bui)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Text(self.newsService.isLoading
                         ? AppLanguage.text("正在加载精选内容流…", en: "Loading reel feed…")
                         : AppLanguage.text("暂无匹配内容", en: "No matching stories"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(self.secondaryInk)
                    Button {
                        self.triggerFeedRefresh()
                    } label: {
                        Label(AppLanguage.text("刷新换一批", en: "Refresh Feed"), systemImage: "arrow.clockwise")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(self.tokens.onAccentInk)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(self.tokens.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    
    private func shortVideoReelStage(story: AIHotNewsItem, index: Int, totalCount: Int, bui: BeautifulUITokens) -> some View {
        let blocks = self.newsService.articleContents[story.id]?.blocks ?? []
        let isLoadingArticle = self.newsService.loadingArticleIDs.contains(story.id)
        let cover: NSImage? = AIHotNewsService.isSyntheticOGCardURL(story.coverURLString)
            ? nil
            : self.newsService.cachedCoverImage(for: story)
        let isSaved = self.newsService.isBookmarked(story)
        
        return HStack(spacing: 14) {
            // Centered Focused Reel Card
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        if let cover {
                            ZStack(alignment: .bottomLeading) {
                                Image(nsImage: cover)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFill()
                                    .frame(height: 210)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                
                                LinearGradient(
                                    colors: [.clear, Color.black.opacity(0.55)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 76)
                                
                                HStack(spacing: 8) {
                                    Text(story.resolvedCategory == .xSocial ? "X" : story.resolvedCategory.badgeLabel)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(self.tokens.accent, in: Capsule())
                                    
                                    Text(story.displayPublisherLabel)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.92))
                                    
                                    Spacer()
                                    
                                    Text("\(index + 1) / \(totalCount)")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced).monospacedDigit())
                                        .foregroundStyle(.white.opacity(0.9))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.black.opacity(0.45), in: Capsule())
                                }
                                .padding(12)
                            }
                        } else {
                            HStack(spacing: 8) {
                                Text(story.resolvedCategory == .xSocial ? "X" : story.resolvedCategory.badgeLabel)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(self.tokens.onAccentInk)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(self.tokens.accent, in: Capsule())
                                
                                Text(story.displayPublisherLabel)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(self.secondaryInk)
                                
                                Spacer()
                                
                                Text("\(index + 1) / \(totalCount)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced).monospacedDigit())
                                    .foregroundStyle(self.secondaryInk)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(self.tokens.inset, in: Capsule())
                            }
                            .padding(.top, 4)
                        }
                        
                        Text(story.title)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(self.tokens.primaryInk)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        
                        if let summary = story.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                            Text(summary)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(self.secondaryInk)
                                .lineSpacing(5)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(self.tokens.inset.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .textSelection(.enabled)
                        }
                        
                        if isLoadingArticle && blocks.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(AppLanguage.text("正在加载原文精读内容…", en: "Loading full article…"))
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(self.mutedInk)
                            }
                            .padding(.vertical, 8)
                        } else if blocks.isEmpty {
                            HStack(spacing: 10) {
                                Text(AppLanguage.text("该站点限制正文直读，可点右栏 AI 陪读或浏览器查看原文。", en: "Preview limited; ask the side AI or open source."))
                                    .font(.system(size: 12))
                                    .foregroundStyle(self.mutedInk)
                                Spacer()
                                Button(AppLanguage.text("重新抓取", en: "Retry")) {
                                    Task { await self.newsService.refetchArticleExcerpt(for: story) }
                                }
                                .controlSize(.small)
                            }
                            .padding(10)
                            .background(self.tokens.inset.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            VStack(alignment: .leading, spacing: 11) {
                                ForEach(Array(blocks.prefix(24).enumerated()), id: \.offset) { _, block in
                                    self.shortFeedArticleBlockView(block)
                                }
                            }
                        }
                    }
                    .padding(cover == nil ? 18 : 0)
                    .padding(.horizontal, cover == nil ? 0 : 18)
                    .padding(.bottom, 18)
                }
            }
            .id(story.id)
            .transition(.asymmetric(
                insertion: .move(edge: self.shortFeedTransitionEdge).combined(with: .opacity),
                removal: .opacity
            ))
            .frame(maxWidth: 660, maxHeight: .infinity)
            .background(bui.surface.opacity(self.hasCustomBackground ? 0.90 : 1.0), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(bui.line, lineWidth: 0.9)
            )
            .shadow(color: Color.black.opacity(self.tokens.isDark ? 0.28 : 0.06), radius: 14, y: 5)
            
            // Douyin-Style Floating Vertical Action Rail
            VStack(spacing: 12) {
                Spacer()
                
                Button {
                    self.stepShortFeed(delta: -1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(index > 0 ? self.tokens.primaryInk : self.mutedInk.opacity(0.45))
                        .frame(width: 40, height: 40)
                        .background(bui.surface, in: Circle())
                        .overlay(Circle().strokeBorder(bui.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .disabled(index <= 0)
                .pointerStyle(.link)
                .help(AppLanguage.text("上一条 (↑)", en: "Previous (↑)"))
                
                Button {
                    self.stepShortFeed(delta: 1)
                } label: {
                    Image(systemName: index + 1 >= totalCount ? "arrow.clockwise" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(self.tokens.onAccentInk)
                        .frame(width: 42, height: 42)
                        .background(self.tokens.accent, in: Circle())
                        .shadow(color: self.tokens.accent.opacity(0.28), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(index + 1 >= totalCount
                      ? AppLanguage.text("换一批新内容 (↓)", en: "Load Fresh Batch (↓)")
                      : AppLanguage.text("下一条 (↓)", en: "Next (↓)"))
                
                Button {
                    self.newsService.toggleBookmark(story)
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(isSaved ? self.tokens.accent : self.secondaryInk)
                        .frame(width: 38, height: 38)
                        .background(bui.surface, in: Circle())
                        .overlay(Circle().strokeBorder(bui.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(AppLanguage.text("收藏", en: "Bookmark"))
                
                Button {
                    if let url = URL(string: story.urlString) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(self.secondaryInk)
                        .frame(width: 38, height: 38)
                        .background(bui.surface, in: Circle())
                        .overlay(Circle().strokeBorder(bui.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(AppLanguage.text("在浏览器打开原文", en: "Open Original"))
                
                Button {
                    withAnimation(DashMotion.quick) {
                        self.isSideAICollapsed.toggle()
                    }
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(self.isSideAICollapsed ? self.secondaryInk : self.tokens.accent)
                        .frame(width: 38, height: 38)
                        .background(bui.surface, in: Circle())
                        .overlay(Circle().strokeBorder(self.isSideAICollapsed ? bui.line : self.tokens.accent.opacity(0.45), lineWidth: 0.9))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(self.isSideAICollapsed ? AppLanguage.text("显示 AI 陪读", en: "Show AI Companion") : AppLanguage.text("收起 AI 陪读", en: "Hide AI Companion"))
                
                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
    
    
    @ViewBuilder
    private func shortFeedArticleBlockView(_ block: NewsArticleBlock) -> some View {
        switch block {
            case .heading(let level, let text):
                Text(text)
                    .font(.system(size: level <= 2 ? 16 : 14.5, weight: .bold))
                    .foregroundStyle(self.tokens.primaryInk)
                    .padding(.top, 4)
                    .textSelection(.enabled)
            case .paragraph(let text):
                Text(text)
                    .font(.system(size: 14.5))
                    .lineSpacing(6)
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.92))
                    .textSelection(.enabled)
            case .quote(let text):
                Text(text)
                    .font(.system(size: 13.5))
                    .lineSpacing(5)
                    .foregroundStyle(self.secondaryInk)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(self.tokens.accent).frame(width: 2.5)
                    }
                    .textSelection(.enabled)
            case .code(let text):
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(self.tokens.primaryInk)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .textSelection(.enabled)
            case .list(let items):
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                        HStack(alignment: .top, spacing: 7) {
                            Text("•")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(self.tokens.accent)
                            Text(text)
                                .font(.system(size: 14))
                                .lineSpacing(5)
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.92))
                                .textSelection(.enabled)
                        }
                    }
                }
        }
    }
    
    
    private func shortFeedCompanionPanel(for story: AIHotNewsItem, bui: BeautifulUITokens) -> some View {
        let quickPrompts: [(label: String, prompt: String)] = [
            (AppLanguage.text("30秒速读", en: "30s TLDR"), AppLanguage.text("用 3-4 条精炼要点告诉我这篇文章最核心的信息", en: "Give me 3-4 bullet takeaways of this article")),
            (AppLanguage.text("深挖逻辑", en: "Why It Matters"), AppLanguage.text("这篇文章背后揭示了什么行业趋势或底层逻辑？", en: "What underlying trend or implication does this reveal?")),
            (AppLanguage.text("关联影响", en: "Impact"), AppLanguage.text("对科技/市场/相关公司有什么值得关注的实际影响？", en: "What practical market or tech impact does this have?")),
        ]
        
        return VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(quickPrompts, id: \.label) { chip in
                        Button {
                            guard self.newsService.streamingChatItemID != story.id else { return }
                            Task {
                                await self.newsService.sendChatFollowUp(
                                    chip.prompt,
                                    for: story,
                                    quote: "",
                                    effort: .simple,
                                    selectedModel: self.selectedModel
                                )
                            }
                        } label: {
                            Text(chip.label)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(self.tokens.accentText)
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(self.tokens.accent.opacity(0.11), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
            }
            .background(bui.surface)
            
            Rectangle().fill(bui.line).frame(height: 1)
            
            self.aiChatPane(for: story, isCenteredCard: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var editorialFeedStage: some View {
        let items = self.displayedItems
        let refreshToken = self.newsService.feedRefreshToken
        return GeometryReader { geo in
            let horizontalPad: CGFloat = geo.size.width >= 1000 ? 28 : 18
            let innerW = min(1440, max(320, geo.size.width - horizontalPad * 2))
            let colCount = Self.columnsForWidth(innerW)
            let colSpacing: CGFloat = 14
            let cardWidth = max(140, (innerW - CGFloat(colCount - 1) * colSpacing) / CGFloat(colCount))
            let coverHeight = max(124, min(176, (cardWidth * 0.62).rounded()))
            
            if items.isEmpty {
                VStack(spacing: 12) {
                    Text(self.newsService.isLoading
                         ? AppLanguage.text("正在加载最新资讯…", en: "Loading articles…")
                         : (self.searchText.isEmpty
                            ? AppLanguage.text("该分类暂无资讯", en: "No articles in this category")
                            : AppLanguage.text("未找到匹配“\(self.searchText)”的资讯", en: "No matching articles")))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(self.secondaryInk)
                    
                    HStack(spacing: 10) {
                        if !self.searchText.isEmpty && self.crossCategorySearchMatchCount > 0 {
                            Button {
                                self.selectedCategory = .all
                                self.newsService.selectedCategory = .all
                            } label: {
                                Text(AppLanguage.text("在「全部」中查看 \(self.crossCategorySearchMatchCount) 条结果", en: "Search All (\(self.crossCategorySearchMatchCount))"))
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(self.tokens.onAccentInk)
                                    .padding(.horizontal, 14)
                                    .frame(height: 32)
                                    .background(self.tokens.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        } else if !self.newsService.isLoading {
                            Button {
                                self.triggerFeedRefresh()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11.5, weight: .medium))
                                    Text(AppLanguage.text("刷新拉取", en: "Refresh Feed"))
                                        .font(.system(size: 12.5, weight: .medium))
                                }
                                .foregroundStyle(self.tokens.primaryInk)
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(self.tokens.hairline, lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 14) {
                            // Compact Editorial Status Strip
                            HStack(spacing: 8) {
                                Text(self.selectedCategory == .all
                                     ? AppLanguage.text("精选信息流 · \(items.count) 篇", en: "Curated Stream · \(items.count)")
                                     : AppLanguage.text("\(self.selectedCategory.label) · \(items.count) 篇", en: "\(self.selectedCategory.label) · \(items.count)"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(self.secondaryInk)
                                
                                if let updatedAt = self.newsService.lastUpdatedAt {
                                    Text("·")
                                        .foregroundStyle(self.mutedInk)
                                    Text(AppLanguage.text("更新于 \(Self.relativeTimeString(from: updatedAt)) 前", en: "Updated \(Self.relativeTimeString(from: updatedAt)) ago"))
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(self.mutedInk)
                                }
                                
                                Spacer(minLength: 0)
                                
                                if !self.searchText.isEmpty {
                                    Text(AppLanguage.text("点击卡片进入正文精读", en: "Click any card to read"))
                                        .font(.system(size: 11))
                                        .foregroundStyle(self.mutedInk)
                                }
                            }
                            .id("news-feed-top")
                            
                            let gridColumns = Array(repeating: GridItem(.flexible(), spacing: colSpacing, alignment: .top), count: colCount)
                            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 14) {
                                ForEach(items) { item in
                                    XiaohongshuNewsCard(
                                        item: item,
                                        cover: self.newsService.cachedCoverImage(for: item),
                                        coverHeight: coverHeight,
                                        showCategoryBadge: self.selectedCategory == .all,
                                        isRead: self.newsService.isRead(item),
                                        isBookmarked: self.newsService.isBookmarked(item),
                                        hasAIBrief: !(self.newsService.aiBriefs[item.id] ?? "").isEmpty,
                                        tokens: self.tokens,
                                        secondaryInk: self.secondaryInk,
                                        mutedInk: self.mutedInk,
                                        onAppearLoadCover: {
                                            self.newsService.requestCoverLoad(for: item)
                                        },
                                        onToggleBookmark: {
                                            self.newsService.toggleBookmark(item)
                                        }
                                    ) {
                                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                                            self.selectedItemID = item.id
                                        }
                                    }
                                    .equatable()
                                }
                            }
                            .id("news-grid-\(self.selectedCategory.rawValue)-\(refreshToken)")
                            .transition(.opacity)
                            .animation(DashMotion.quick, value: refreshToken)
                            
                            // Bottom Douyin / Xiaohongshu-style Refresh Prompt
                            HStack {
                                Spacer()
                                Button {
                                    self.triggerFeedRefresh()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: self.newsService.isLoading ? "hourglass" : "arrow.clockwise")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text(AppLanguage.text("看完了，换一批新内容", en: "Load Fresh Batch"))
                                            .font(.system(size: 12.5, weight: .medium))
                                    }
                                    .foregroundStyle(self.secondaryInk)
                                    .padding(.horizontal, 16)
                                    .frame(height: 34)
                                    .background(self.tokens.card, in: Capsule())
                                    .overlay(Capsule().strokeBorder(self.tokens.hairline, lineWidth: 0.8))
                                }
                                .buttonStyle(.plain)
                                .disabled(self.newsService.isLoading)
                                .pointerStyle(.link)
                                Spacer()
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                        }
                        .padding(.horizontal, horizontalPad)
                        .padding(.top, 14)
                        .padding(.bottom, 16)
                        .frame(maxWidth: innerW + horizontalPad * 2, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .onChange(of: self.feedScrollResetToken) { _, _ in
                        withAnimation(DashMotion.quick) {
                            scrollProxy.scrollTo("news-feed-top", anchor: .top)
                        }
                    }
                }
            }
        }
    }
    
    
    // MARK: - Balanced Native Editorial Reader + Polished AI Chat Split
    
    private func detailAndChatStage(for item: AIHotNewsItem) -> some View {
        let blocks = self.newsService.resolvedArticleBlocks(for: item)
        let summaryText = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isLoadingArticle = self.newsService.loadingArticleIDs.contains(item.id)
            || (blocks.isEmpty && summaryText.isEmpty && !self.newsService.hasFinishedDetailFetch(for: item.id))
        let neighbors = self.adjacentItems
        let relatedItems: [AIHotNewsItem] = {
            let excludeIDs: Set<String> = [item.id]
            let sameCategory = self.displayedItems.filter { !excludeIDs.contains($0.id) && $0.resolvedCategory == item.resolvedCategory }
            let fallback = self.displayedItems.filter { !excludeIDs.contains($0.id) }
            let pool = sameCategory.count >= 3 ? sameCategory : fallback
            return Array(pool.prefix(4))
        }()
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
        let refetchHandler: () -> Void = {
            Task {
                await self.newsService.refetchArticleExcerpt(for: item)
            }
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
                        hasAttemptedFetch: self.newsService.hasFinishedDetailFetch(for: item.id),
                        previousItem: neighbors.previous,
                        nextItem: neighbors.next,
                        relatedItems: relatedItems,
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
                        onQuoteToAI: quoteHandler,
                        onRefetchArticle: refetchHandler
                    )
                    .equatable()
                    .frame(height: max(240, geo.size.height * 0.52))
                    
                    Rectangle()
                        .fill(bui.line)
                        .frame(height: 1)
                    
                    self.aiChatPane(for: item, isCenteredCard: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // Harmonized full-bleed editorial split stage (~58 / 42)
                let useCenteredCard = !self.isEmbeddedInPane && geo.size.width >= 960
                let stageWidth = useCenteredCard ? min(1400, geo.size.width - 28) : geo.size.width
                let minChatWidth: CGFloat = 360
                let maxChatWidth: CGFloat = max(minChatWidth, min(stageWidth * 0.48, stageWidth - 460))
                let proposedChatWidth = stageWidth * self.chatWidthFraction
                let chatWidth = min(maxChatWidth, max(minChatWidth, proposedChatWidth))
                
                let splitContent = HStack(spacing: 0) {
                    NewsEditorialArticlePane(
                        item: item,
                        cover: readerCover,
                        blocks: blocks,
                        isLoadingArticle: isLoadingArticle,
                        hasAttemptedFetch: self.newsService.hasFinishedDetailFetch(for: item.id),
                        previousItem: neighbors.previous,
                        nextItem: neighbors.next,
                        relatedItems: relatedItems,
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
                        onQuoteToAI: quoteHandler,
                        onRefetchArticle: refetchHandler
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
                        .background(bui.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(bui.line, lineWidth: 1)
                        )
                        .shadow(
                            color: Color.black.opacity(self.tokens.isDark ? 0.34 : 0.05),
                            radius: 16,
                            x: 0,
                            y: 6
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
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
        
        let slashCommands: [BeautifulAgentSlashCommandPayload] = [
            .init(key: "tldr", name: "/tldr", desc: AppLanguage.text("快速提炼核心事实与关键数字", en: "Quick key takeaways"), insertText: AppLanguage.text("请快速用 3-5 条要点提炼这篇文章最核心的事实与关键数字", en: "Quickly summarize the core facts in 3-5 bullets")),
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
            placeholder: AppLanguage.text("快速提问、生成摘要，或选中左侧段落引用提问…", en: "Ask for a quick summary or follow up…"),
            greetingName: AppLanguage.text("快速精读", en: "Quick Brief"),
            greetingSubtitle: nil,
            articleTitle: item.title,
            articleSource: sourceNote,
            quotedExcerpt: self.newsQuotedExcerpt,
            availableModels: mappedModels,
            selectedModelID: selectedTitle,
            selectedModelTitle: selectedTitle,
            effort: nil,
            suggestions: [],
            contextSources: [],
            slashCommands: slashCommands
        )
    }
    
    
    private func buildNewsAgentCallbacks(for item: AIHotNewsItem) -> BeautifulAgentWebActionCallbacks {
        let botStore = AIBotStore.shared
        var cb = BeautifulAgentWebActionCallbacks()
        cb.onSend = { prompt, quote in
            guard self.newsService.streamingChatItemID != item.id else { return }
            let effectiveQuote = quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? self.newsQuotedExcerpt
                : quote
            self.newsQuotedExcerpt = nil
            Task {
                await self.newsService.sendChatFollowUp(
                    prompt,
                    for: item,
                    quote: effectiveQuote,
                    effort: .simple,
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
                effort: .simple,
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
        self.newsService.recordBrowsingHistory(item)
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
    let hasAttemptedFetch: Bool
    let previousItem: AIHotNewsItem?
    let nextItem: AIHotNewsItem?
    let relatedItems: [AIHotNewsItem]
    let bodyFontSize: CGFloat
    let tokens: StudioColorTokens
    let bui: BeautifulUITokens
    let secondaryInk: Color
    let mutedInk: Color
    let onSelectItem: (String) -> Void
    let onQuoteToAI: (String) -> Void
    let onRefetchArticle: () -> Void
    
    @State private var hoveredBlockIndex: Int? = nil
    @State private var hoveredRelatedID: String? = nil
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.cover === rhs.cover
            && lhs.blocks == rhs.blocks
            && lhs.isLoadingArticle == rhs.isLoadingArticle
            && lhs.hasAttemptedFetch == rhs.hasAttemptedFetch
            && lhs.previousItem?.id == rhs.previousItem?.id
            && lhs.nextItem?.id == rhs.nextItem?.id
            && lhs.relatedItems.map(\.id) == rhs.relatedItems.map(\.id)
            && lhs.tokens.isDark == rhs.tokens.isDark
    }
    
    
    /// Separates trailing `"来源：..."` / `"Source: ..."` attribution lines from body blocks so they render
    /// inside a dedicated clickable source footer card instead of plain body prose.
    private var parsedContent: (bodyBlocks: [NewsArticleBlock], sourceAttribution: String?, totalChars: Int) {
        var cleaned: [NewsArticleBlock] = []
        var sourceLine: String?
        var charCount = 0
        
        for (idx, block) in self.blocks.enumerated() {
            if case .paragraph(let raw) = block {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = trimmed.lowercased()
                let isSourceMeta = (idx == self.blocks.count - 1 || idx >= self.blocks.count - 2)
                    && (trimmed.hasPrefix("来源：") || trimmed.hasPrefix("来源:") || lower.hasPrefix("source:") || lower.hasPrefix("via:"))
                if isSourceMeta {
                    sourceLine = trimmed
                        .replacingOccurrences(of: #"^(来源[：:]\s*|source:\s*|via:\s*)"#, with: "", options: [.regularExpression, .caseInsensitive])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continue
                }
                charCount += trimmed.count
            } else {
                switch block {
                    case .heading(_, let t), .quote(let t), .code(let t):
                        charCount += t.count
                    case .list(let list):
                        charCount += list.reduce(0) { $0 + $1.count }
                    case .paragraph:
                        break
                }
            }
            cleaned.append(block)
        }
        return (cleaned, sourceLine, charCount)
    }
    
    
    var body: some View {
        let publisher = self.item.displayPublisherLabel
        let summaryText = self.item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parsed = self.parsedContent
        let effectiveSourceText: String? = {
            if let attr = parsed.sourceAttribution, !attr.isEmpty {
                return attr
            }
            let host = self.item.url?.host()?.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            if !publisher.isEmpty, let host, !publisher.localizedCaseInsensitiveContains(host) {
                return "\(publisher) · \(host)"
            }
            if !publisher.isEmpty { return publisher }
            return host
        }()
        let isShortBrief = !self.isLoadingArticle && self.cover == nil && parsed.totalChars < 420 && summaryText.count < 420
        
        return ScrollViewReader { readerProxy in
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Editorial Metadata Header
                        HStack(alignment: .center, spacing: 10) {
                            Text(self.item.resolvedCategory.label)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(self.bui.accentInk)
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(self.bui.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            
                            if !publisher.isEmpty {
                                Text(publisher)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(self.bui.ink2)
                                    .lineLimit(1)
                            }
                            
                            if let date = self.item.publishedAt {
                                Text("·")
                                    .font(.system(size: 13))
                                    .foregroundStyle(self.bui.ink3)
                                Text(DashboardNewsCenterView.relativeTimeString(from: date))
                                    .font(.system(size: 13, design: .monospaced).monospacedDigit())
                                    .foregroundStyle(self.bui.ink3)
                            }
                            
                            Spacer(minLength: 0)
                        }
                        .id("article-top")
                        .padding(.bottom, 14)
                        
                        // Editorial Headline
                        Text(self.item.title)
                            .font(.system(size: 24, weight: .bold))
                            .tracking(-0.35)
                            .foregroundStyle(self.bui.ink)
                            .lineSpacing(7)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 18)
                        
                        Rectangle()
                            .fill(self.bui.line)
                            .frame(height: 1)
                            .padding(.bottom, 22)
                        
                        // Real Editorial Cover Image (if any)
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
                                .padding(.bottom, 22)
                        }
                        
                        // Main Article Body
                        if !parsed.bodyBlocks.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(Array(parsed.bodyBlocks.enumerated()), id: \.offset) { idx, block in
                                    self.articleBlockView(block, index: idx)
                                }
                            }
                        } else if !summaryText.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(summaryText)
                                    .font(.system(size: self.bodyFontSize, weight: .regular))
                                    .foregroundStyle(self.bui.ink.opacity(0.92))
                                    .lineSpacing(9)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                if self.isLoadingArticle {
                                    self.loadingPlaceholder
                                }
                            }
                        } else if self.isLoadingArticle {
                            self.loadingPlaceholder
                        }
                        
                        // Extraction incomplete / retry notice when page returned very short or empty text
                        if !self.isLoadingArticle && self.hasAttemptedFetch && parsed.totalChars < 120 {
                            self.incompleteExtractionNoticeCard
                                .padding(.top, 18)
                        }
                        
                        // Clickable Source Attribution Card
                        let displaySource = effectiveSourceText ?? self.item.url?.host() ?? ""
                        if !displaySource.isEmpty || self.item.url != nil {
                            self.sourceAttributionCard(
                                sourceText: displaySource.isEmpty ? AppLanguage.text("外部原文链接", en: "External Source") : displaySource,
                                url: self.item.url
                            )
                            .padding(.top, 24)
                        }
                        
                        // Related News Briefs Strip (prevents awkward white void on short news summaries)
                        if isShortBrief, !self.relatedItems.isEmpty {
                            self.relatedReadingSection(items: self.relatedItems) { targetID in
                                self.onSelectItem(targetID)
                                readerProxy.scrollTo("article-top", anchor: .top)
                            }
                            .padding(.top, 28)
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.top, 26)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 660, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Pinned Editorial Navigation Footer (always anchored cleanly at bottom)
                if self.previousItem != nil || self.nextItem != nil {
                    Rectangle()
                        .fill(self.bui.line)
                        .frame(height: 1)
                    
                    HStack(spacing: 0) {
                        if let prev = self.previousItem {
                            self.footerNavButton(prev, isNext: false) {
                                self.onSelectItem(prev.id)
                                readerProxy.scrollTo("article-top", anchor: .top)
                            }
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                        
                        Rectangle()
                            .fill(self.bui.line)
                            .frame(width: 1, height: 22)
                        
                        if let next = self.nextItem {
                            self.footerNavButton(next, isNext: true) {
                                self.onSelectItem(next.id)
                                readerProxy.scrollTo("article-top", anchor: .top)
                            }
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 50)
                    .background(self.bui.page)
                }
            }
            .background(self.bui.surface)
            .onChange(of: self.item.id) { _, _ in
                self.hoveredBlockIndex = nil
                readerProxy.scrollTo("article-top", anchor: .top)
            }
        }
    }
    
    
    @ViewBuilder
    private var incompleteExtractionNoticeCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(AppLanguage.text("原网页正文内容较少或存在访问限制", en: "Limited article preview available"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(self.bui.ink)
                Text(AppLanguage.text("可尝试重新多路抓取，或直接在浏览器中阅读完整原文。", en: "Try refetching full text or open the original page."))
                    .font(.system(size: 12))
                    .foregroundStyle(self.bui.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Button {
                self.onRefetchArticle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text(AppLanguage.text("重新抓取", en: "Refetch"))
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(self.bui.accentInk)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(self.bui.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(self.bui.lineStrong, lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(self.bui.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(self.bui.line, lineWidth: 0.8))
    }
    
    
    @ViewBuilder
    private func sourceAttributionCard(sourceText: String, url: URL?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLanguage.text("内容来源", en: "Source"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(self.bui.ink3)
                Text(sourceText)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(self.bui.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if let url {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: 5) {
                        Text(AppLanguage.text("阅读原文", en: "Read Original"))
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(self.bui.accentInk)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(self.bui.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(self.bui.lineStrong, lineWidth: 0.8)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(self.bui.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(self.bui.line, lineWidth: 0.8)
        )
    }
    
    
    private func relatedReadingSection(items: [AIHotNewsItem], onPick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLanguage.text("延伸阅读", en: "More in Feed"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(self.bui.ink2)
            
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, related in
                    if idx > 0 {
                        Rectangle()
                            .fill(self.bui.line)
                            .frame(height: 0.75)
                            .padding(.horizontal, 12)
                    }
                    let isHovered = (self.hoveredRelatedID == related.id)
                    Button {
                        onPick(related.id)
                    } label: {
                        HStack(spacing: 10) {
                            Text(related.title)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(isHovered ? self.bui.ink : self.bui.ink.opacity(0.86))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            if let date = related.publishedAt {
                                Text(DashboardNewsCenterView.relativeTimeString(from: date))
                                    .font(.system(size: 12.5, design: .monospaced).monospacedDigit())
                                    .foregroundStyle(self.bui.ink3)
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(self.bui.ink3)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isHovered ? self.bui.inset : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .onHover { hovering in
                        self.hoveredRelatedID = hovering ? related.id : (self.hoveredRelatedID == related.id ? nil : self.hoveredRelatedID)
                    }
                }
            }
            .padding(4)
            .background(self.bui.page, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(self.bui.line, lineWidth: 0.8)
            )
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
                        .lineSpacing(9)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isHovered ? self.bui.inset.opacity(0.75) : Color.clear)
                        )
                    
                    if isHovered && text.count >= 12 {
                        self.quoteToAIButton(text: text)
                            .padding(.top, 5)
                            .padding(.trailing, 8)
                    }
                }
                .padding(.horizontal, -10)
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
                            .font(.system(size: 14.5, weight: .regular))
                            .foregroundStyle(self.bui.ink2)
                            .lineSpacing(7)
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
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
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
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(self.bui.ink3)
                                .frame(width: 4.5, height: 4.5)
                                .padding(.top, 9)
                            
                            Text(line)
                                .font(.system(size: self.bodyFontSize, weight: .regular))
                                .foregroundStyle(self.bui.ink.opacity(0.90))
                                .lineSpacing(8)
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
                    .font(.system(size: 11, weight: .semibold))
                Text(AppLanguage.text("引用提问", en: "Quote"))
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(self.bui.accentInk)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(self.bui.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(self.bui.lineStrong, lineWidth: 0.8))
            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .transition(.opacity)
    }
    
    
    private var loadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(self.tokens.inset)
                .frame(maxWidth: .infinity)
                .frame(height: 13)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(self.tokens.inset)
                .frame(maxWidth: .infinity)
                .frame(height: 13)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(self.tokens.inset)
                .frame(width: 240, height: 13)
        }
        .padding(.vertical, 6)
    }
    
    
    private func footerNavButton(_ item: AIHotNewsItem, isNext: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if !isNext {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(self.bui.ink3)
                }
                
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(self.bui.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: isNext ? .trailing : .leading)
                
                if isNext {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(self.bui.ink3)
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
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


// MARK: - Editorial Magazine News Card

private struct XiaohongshuNewsCard: View, Equatable {
    
    let item: AIHotNewsItem
    let cover: NSImage?
    let coverHeight: CGFloat
    let showCategoryBadge: Bool
    let isRead: Bool
    let isBookmarked: Bool
    let hasAIBrief: Bool
    let tokens: StudioColorTokens
    let secondaryInk: Color
    let mutedInk: Color
    let onAppearLoadCover: () -> Void
    let onToggleBookmark: () -> Void
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.item.title == rhs.item.title
            && lhs.item.summary == rhs.item.summary
            && lhs.cover === rhs.cover
            && abs(lhs.coverHeight - rhs.coverHeight) < 0.5
            && lhs.showCategoryBadge == rhs.showCategoryBadge
            && lhs.isRead == rhs.isRead
            && lhs.isBookmarked == rhs.isBookmarked
            && lhs.hasAIBrief == rhs.hasAIBrief
            && lhs.tokens.isDark == rhs.tokens.isDark
    }
    
    
    private var accentColor: Color {
        switch self.item.resolvedCategory {
            case .finance:
                return self.tokens.heat3
            case .xSocial:
                return Color(red: 0.212, green: 0.478, blue: 0.612)
            case .ai, .all:
                let seed = Int(DashboardNewsCenterView.stableSeed(for: self.item.id) % 2)
                return seed == 0 ? self.tokens.accent : self.tokens.secondaryAccent
        }
    }
    
    
    var body: some View {
        let publisher = self.item.displayPublisherLabel
        let sourceLabel = publisher.isEmpty ? self.item.resolvedCategory.label : publisher
        let initialChar = String(sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
        let summarySnippet = self.item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let textBodyHeight: CGFloat = 112
        
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
                    self.editorialCoverTile(sourceLabel: sourceLabel, initialChar: initialChar)
                        .frame(height: self.coverHeight)
                }
                
                HStack(spacing: 6) {
                    if self.showCategoryBadge || self.cover != nil {
                        Text(self.item.resolvedCategory == .xSocial ? "X" : self.item.resolvedCategory.badgeLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(self.tokens.primaryInk)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(self.tokens.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    
                    Spacer(minLength: 4)
                    
                    if self.isHovered || self.isBookmarked {
                        Button {
                            self.onToggleBookmark()
                        } label: {
                            Image(systemName: self.isBookmarked ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(self.isBookmarked ? self.tokens.accent : self.tokens.primaryInk)
                                .frame(width: 22, height: 22)
                                .background(self.tokens.card.opacity(0.90), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    } else if self.hasAIBrief {
                        Text("AI")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(self.tokens.onAccentInk)
                            .padding(.horizontal, 5)
                            .frame(height: 17)
                            .background(self.tokens.accent, in: Capsule())
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
            
            VStack(alignment: .leading, spacing: 6) {
                Text(self.item.title)
                    .font(.system(size: 13.5, weight: self.isRead ? .medium : .semibold))
                    .foregroundStyle(self.isRead ? self.secondaryInk : self.tokens.primaryInk)
                    .lineLimit(2)
                    .lineSpacing(2.5)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                
                if !summarySnippet.isEmpty {
                    Text(summarySnippet)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(self.mutedInk)
                        .lineLimit(2)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                
                Spacer(minLength: 2)
                
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.secondaryInk)
                        .lineLimit(1)
                    
                    Spacer(minLength: 4)
                    
                    if let heat = self.item.heatScore, heat > 0 {
                        Text("\(heat)°")
                            .font(.system(size: 10, weight: .medium, design: .monospaced).monospacedDigit())
                            .foregroundStyle(self.accentColor)
                    }
                    
                    if let date = self.item.publishedAt {
                        Text(DashboardNewsCenterView.relativeTimeString(from: date))
                            .font(.system(size: 10.5, design: .monospaced).monospacedDigit())
                            .foregroundStyle(self.mutedInk)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(height: textBodyHeight, alignment: .topLeading)
        }
        .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    self.isHovered ? self.tokens.hairlineStrong : self.tokens.hairline,
                    lineWidth: 0.9
                )
        )
        .shadow(color: self.tokens.cardShadow, radius: self.isHovered ? 8 : 4, x: 0, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onTapGesture {
            self.onTap()
        }
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
    
    
    private func editorialCoverTile(sourceLabel: String, initialChar: String) -> some View {
        let accent = self.accentColor
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    accent.opacity(self.tokens.isDark ? 0.24 : 0.13),
                    accent.opacity(self.tokens.isDark ? 0.08 : 0.04),
                    self.tokens.inset,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Subtle editorial monogram watermark
            Text(initialChar.isEmpty ? "N" : initialChar)
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(accent.opacity(self.tokens.isDark ? 0.12 : 0.08))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 14)
                .padding(.top, 12)
            
            VStack(alignment: .leading, spacing: 5) {
                Capsule()
                    .fill(accent.opacity(0.75))
                    .frame(width: 24, height: 3)
                
                Text(sourceLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.86))
                    .lineLimit(1)
            }
            .padding(12)
        }
    }
}
