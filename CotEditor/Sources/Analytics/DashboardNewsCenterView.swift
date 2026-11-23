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
    
    @State private var selectedCategory: NewsFeedCategory = .all
    @State private var searchText: String = ""
    @State private var selectedItemID: String?
    @State private var reasoningEffort: NewsReasoningEffort = .balanced
    @State private var availableModels: [NewsChatModelOption] = []
    @State private var selectedModel: NewsChatModelOption?
    @State private var isModelPopoverOpen: Bool = false
    @State private var copiedMessageID: String?
    @State private var chatWidthFraction: CGFloat = 0.38
    @State private var dragStartChatFraction: CGFloat?
    @State private var isSplitDividerHovering: Bool = false
    @State private var lastAutoScrollAt: Date = .distantPast
    @Namespace private var topCategoryNamespace
    
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
                    .transition(DashMotion.pageTransition)
            } else {
                self.xiaohongshuCardGridStage
                    .transition(DashMotion.pageTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(self.tokens.canvasTop)
        .onAppear {
            self.selectedCategory = self.initialCategory ?? self.newsService.selectedCategory
            if let initialSearchQuery, !initialSearchQuery.isEmpty {
                self.searchText = initialSearchQuery
            }
            self.selectedItemID = self.initialSelectedID
            self.reloadAvailableModels()
            self.syncSelectionSideEffects()
            self.newsService.preloadFeedResources(limit: 20)
            Task {
                await self.newsService.refreshIfNeeded()
            }
        }
        .onChange(of: self.selectedItemID) { _, _ in
            self.isModelPopoverOpen = false
            self.reloadAvailableModels()
            self.syncSelectionSideEffects()
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
                        withAnimation(DashMotion.travel) {
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
                            withAnimation(DashMotion.travel) {
                                self.selectedCategory = category
                                self.newsService.selectedCategory = category
                            }
                        } label: {
                            Text(category == .xSocial ? "X" : category.label)
                                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? self.tokens.onAccentInk : self.secondaryInk)
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                                .background {
                                    if isActive {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(self.tokens.accent)
                                            .matchedGeometryEffect(id: "newsTopCat", in: self.topCategoryNamespace)
                                    }
                                }
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
                
                if let url = self.selectedItem?.url {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 5) {
                            Text(AppLanguage.text("浏览器打开原文", en: "Open Original"))
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10.5, weight: .semibold))
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
    
    
    // MARK: - Harmonious Xiaohongshu Card Grid Feed
    
    private var xiaohongshuCardGridStage: some View {
        let items = self.displayedItems
        return GeometryReader { geo in
            let contentW = min(1320, max(320, geo.size.width - 40))
            let colCount: Int = {
                if contentW >= 1060 { return 4 }
                if contentW >= 740 { return 3 }
                return 2
            }()
            let columns = Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: colCount)
            
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(self.mutedInk.opacity(0.6))
                    Text(self.newsService.isLoading
                         ? AppLanguage.text("正在加载资讯…", en: "Loading articles…")
                         : AppLanguage.text("暂无匹配资讯", en: "No articles"))
                        .font(.system(size: 13))
                        .foregroundStyle(self.mutedInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(items) { item in
                            XiaohongshuNewsCard(
                                item: item,
                                cover: self.newsService.coverImage(for: item),
                                isRead: self.newsService.isRead(item),
                                hasAIBrief: !(self.newsService.aiBriefs[item.id] ?? "").isEmpty,
                                tokens: self.tokens,
                                secondaryInk: self.secondaryInk,
                                mutedInk: self.mutedInk
                            ) {
                                withAnimation(DashMotion.travel) {
                                    self.selectedItemID = item.id
                                }
                            }
                            .equatable()
                        }
                    }
                    .frame(maxWidth: 1320)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .center)
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
        let cover = self.newsService.coverImage(for: item)
        
        return GeometryReader { geo in
            let isCompact = geo.size.width < 840
            if isCompact {
                VStack(spacing: 0) {
                    NewsEditorialArticlePane(
                        item: item,
                        cover: cover,
                        blocks: blocks,
                        isLoadingArticle: isLoadingArticle,
                        previousItem: neighbors.previous,
                        nextItem: neighbors.next,
                        bodyFontSize: self.bodyFontSize,
                        tokens: self.tokens,
                        secondaryInk: self.secondaryInk,
                        mutedInk: self.mutedInk,
                        onSelectItem: { nextID in
                            withAnimation(DashMotion.quick) {
                                self.selectedItemID = nextID
                            }
                        }
                    )
                    .equatable()
                    .frame(height: max(220, geo.size.height * 0.52))
                    
                    Rectangle()
                        .fill(self.tokens.hairline)
                        .frame(height: 1)
                    
                    self.aiChatPane(for: item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // Proportional 62 / 38 split with 120fps non-animated live divider drag
                let minChatWidth: CGFloat = 340
                let maxChatWidth: CGFloat = max(minChatWidth, min(geo.size.width * 0.52, geo.size.width - 480))
                let proposedChatWidth = geo.size.width * self.chatWidthFraction
                let chatWidth = min(maxChatWidth, max(minChatWidth, proposedChatWidth))
                
                HStack(spacing: 0) {
                    NewsEditorialArticlePane(
                        item: item,
                        cover: cover,
                        blocks: blocks,
                        isLoadingArticle: isLoadingArticle,
                        previousItem: neighbors.previous,
                        nextItem: neighbors.next,
                        bodyFontSize: self.bodyFontSize,
                        tokens: self.tokens,
                        secondaryInk: self.secondaryInk,
                        mutedInk: self.mutedInk,
                        onSelectItem: { nextID in
                            withAnimation(DashMotion.quick) {
                                self.selectedItemID = nextID
                            }
                        }
                    )
                    .equatable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    self.newsSplitDivider(totalWidth: geo.size.width)
                    
                    self.aiChatPane(for: item)
                        .frame(width: chatWidth)
                        .frame(maxHeight: .infinity)
                }
                .transaction { tx in
                    if self.dragStartChatFraction != nil {
                        tx.animation = nil
                    }
                }
                .coordinateSpace(name: "newsSplitStage")
            }
        }
    }
    
    private func newsSplitDivider(totalWidth: CGFloat) -> some View {
        let isActive = self.isSplitDividerHovering || self.dragStartChatFraction != nil
        return ZStack {
            Rectangle()
                .fill(isActive ? self.tokens.accentText.opacity(0.45) : self.tokens.hairline)
                .frame(width: isActive ? 2 : 1)
            
            Capsule()
                .fill(self.secondaryInk.opacity(isActive ? 0.50 : 0.0))
                .frame(width: 3, height: 28)
        }
        .frame(width: 8)
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
                    self.chatWidthFraction = min(0.52, max(0.30, startFraction + deltaFraction))
                }
                .onEnded { _ in
                    self.dragStartChatFraction = nil
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(DashMotion.travel) {
                self.chatWidthFraction = 0.38
            }
        }
    }
    
    
    // MARK: - Right Editorial AI Chat Pane + LeiBox Deep Agent Composer
    
    private func aiChatPane(for item: AIHotNewsItem) -> some View {
        let messages = self.newsService.chatMessages(for: item)
        let isStreaming = (self.newsService.streamingChatItemID == item.id)
        
        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Top-anchored AI Companion Stage (zero empty top void)
                ScrollViewReader { chatProxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        if messages.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(AppLanguage.text("陪读讨论", en: "Reading Companion"))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(self.tokens.primaryInk)
                                
                                VStack(spacing: 8) {
                                    self.editorialStarterRow(
                                        index: "01",
                                        title: AppLanguage.text("提炼核心事实与犀利点评", en: "Core facts & sharp critique"),
                                        disabled: isStreaming
                                    ) {
                                        self.isModelPopoverOpen = false
                                        Task {
                                            await self.newsService.requestAICommentary(
                                                for: item,
                                                effort: self.reasoningEffort,
                                                selectedModel: self.selectedModel
                                            )
                                        }
                                    }
                                    
                                    self.editorialStarterRow(
                                        index: "02",
                                        title: AppLanguage.text("对开发者和创作者有什么实际影响？", en: "Practical impact for builders?"),
                                        disabled: isStreaming
                                    ) {
                                        self.isModelPopoverOpen = false
                                        Task {
                                            await self.newsService.sendChatFollowUp(
                                                "结合一线开发者和创作者视角，用清晰 Markdown 拆解这件事有什么直接影响或能立刻用上的机会？",
                                                for: item,
                                                displayUserText: AppLanguage.text("对开发者和创作者有什么实际影响？", en: "Practical impact for builders?"),
                                                effort: self.reasoningEffort,
                                                selectedModel: self.selectedModel
                                            )
                                        }
                                    }
                                    
                                    self.editorialStarterRow(
                                        index: "03",
                                        title: AppLanguage.text("挑挑刺：水分、风险或反面观点", en: "Hype, risks, and counterpoints"),
                                        disabled: isStreaming
                                    ) {
                                        self.isModelPopoverOpen = false
                                        Task {
                                            await self.newsService.sendChatFollowUp(
                                                "别光说好话，用结构化 Markdown 帮我挑挑这件事背后的水分、风险或反面观点。",
                                                for: item,
                                                displayUserText: AppLanguage.text("挑挑刺：水分、风险或反面观点", en: "Hype, risks, and counterpoints"),
                                                effort: self.reasoningEffort,
                                                selectedModel: self.selectedModel
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 20)
                            .frame(maxWidth: 740, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(messages) { msg in
                                    let isTailStreaming = isStreaming && msg.id == messages.last?.id
                                    NewsChatBubbleView(
                                        message: msg,
                                        isStreaming: isTailStreaming,
                                        isCopied: self.copiedMessageID == msg.id,
                                        effortTitle: self.reasoningEffort.title,
                                        tokens: self.tokens,
                                        secondaryInk: self.secondaryInk,
                                        mutedInk: self.mutedInk,
                                        onCopy: {
                                            self.copyAssistantReply(msg)
                                        }
                                    )
                                    .equatable()
                                    .id(msg.id)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 18)
                            .frame(maxWidth: 740, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        
                        if let err = self.newsService.chatErrorMessage, !err.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.orange)
                                
                                Text(err)
                                    .font(.system(size: 12))
                                    .foregroundStyle(self.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Spacer(minLength: 4)
                                
                                Button(AppLanguage.text("去配置", en: "Settings")) {
                                    (NSApp.delegate as? AppDelegate)?.showAIPreferences(nil)
                                }
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(self.tokens.accentText)
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.orange.opacity(0.32), lineWidth: 0.8)
                            )
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                            .frame(maxWidth: 740)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .onTapGesture {
                        if self.isModelPopoverOpen {
                            withAnimation(DashMotion.quick) {
                                self.isModelPopoverOpen = false
                            }
                        }
                    }
                    .onChange(of: messages.last?.text ?? "") { _, _ in
                        guard let lastID = messages.last?.id else { return }
                        let now = Date()
                        guard !isStreaming || now.timeIntervalSince(self.lastAutoScrollAt) >= 0.085 else { return }
                        self.lastAutoScrollAt = now
                        chatProxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
                
                // Isolated LeiBox Deep Agent Composer Dock (keystrokes never dirty reader/messages)
                NewsDeepAgentComposerView(
                    item: item,
                    hasMessages: !messages.isEmpty,
                    isStreaming: isStreaming,
                    activeModelTitle: self.selectedModel?.displayName
                        ?? self.availableModels.first?.displayName
                        ?? AppLanguage.text("选择模型", en: "Model"),
                    effort: self.reasoningEffort,
                    isModelPopoverOpen: self.isModelPopoverOpen,
                    tokens: self.tokens,
                    secondaryInk: self.secondaryInk,
                    mutedInk: self.mutedInk,
                    onTogglePopover: {
                        self.reloadAvailableModels()
                        withAnimation(DashMotion.quick) {
                            self.isModelPopoverOpen.toggle()
                        }
                    },
                    onQuickCommentary: {
                        self.isModelPopoverOpen = false
                        Task {
                            await self.newsService.requestAICommentary(
                                for: item,
                                effort: self.reasoningEffort,
                                selectedModel: self.selectedModel
                            )
                        }
                    },
                    onQuickImpact: {
                        self.isModelPopoverOpen = false
                        Task {
                            await self.newsService.sendChatFollowUp(
                                "结合一线开发者和创作者视角，用清晰 Markdown 拆解这件事有什么直接影响？",
                                for: item,
                                displayUserText: AppLanguage.text("对我有什么实际影响？", en: "Practical Impact"),
                                effort: self.reasoningEffort,
                                selectedModel: self.selectedModel
                            )
                        }
                    },
                    onQuickCounterpoint: {
                        self.isModelPopoverOpen = false
                        Task {
                            await self.newsService.sendChatFollowUp(
                                "别光说好话，用结构化 Markdown 挑挑这件事背后的水分、风险或反面观点。",
                                for: item,
                                displayUserText: AppLanguage.text("挑刺：水分与反面视角", en: "Counterpoint"),
                                effort: self.reasoningEffort,
                                selectedModel: self.selectedModel
                            )
                        }
                    },
                    onClearChat: {
                        self.newsService.clearChat(for: item.id)
                    },
                    onSubmitPrompt: { prompt in
                        guard self.newsService.streamingChatItemID == nil else { return }
                        self.isModelPopoverOpen = false
                        Task {
                            await self.newsService.sendChatFollowUp(
                                prompt,
                                for: item,
                                effort: self.reasoningEffort,
                                selectedModel: self.selectedModel
                            )
                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .frame(maxWidth: 740)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            // Floating Model & Reasoning Effort Popover anchored cleanly above the composer
            if self.isModelPopoverOpen {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(DashMotion.quick) {
                            self.isModelPopoverOpen = false
                        }
                    }
                
                HStack {
                    Spacer(minLength: 0)
                    self.deepAgentModelEffortPopover
                }
                .padding(.trailing, 22)
                .padding(.bottom, 118)
                .frame(maxWidth: 740)
                .frame(maxWidth: .infinity, alignment: .center)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottomTrailing)))
                .zIndex(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(self.tokens.canvasTop)
    }
    
    
    /// Floating Deep Agent Composer popover (`模型` + `推理强度` starry slider) matching `deep_agent_composer.png`.
    private var deepAgentModelEffortPopover: some View {
        let uniqueGateways = Set(self.availableModels.map(\.endpointID)).count
        
        return VStack(alignment: .leading, spacing: 0) {
            // Section 1: 模型
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLanguage.text("模型", en: "Model"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(self.mutedInk)
                    .padding(.horizontal, 6)
                
                if self.availableModels.isEmpty {
                    Button {
                        self.isModelPopoverOpen = false
                        (NSApp.delegate as? AppDelegate)?.showAIPreferences(nil)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 12))
                            Text(AppLanguage.text("前往「API 网关」配置模型…", en: "Configure API Gateway…"))
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(self.tokens.accentText)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 2) {
                            ForEach(self.availableModels) { option in
                                let isSelected = (self.selectedModel?.id == option.id)
                                Button {
                                    self.selectedModel = option
                                } label: {
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(option.modelID)
                                                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                                                .foregroundStyle(isSelected ? self.tokens.primaryInk : self.secondaryInk)
                                                .lineLimit(1)
                                            if uniqueGateways > 1 {
                                                Text(option.endpointName)
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(self.mutedInk)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer(minLength: 4)
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(self.tokens.primaryInk.opacity(0.85))
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: uniqueGateways > 1 ? 36 : 32)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(isSelected ? self.tokens.insetHover : Color.clear)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                            }
                        }
                    }
                    .frame(maxHeight: 164)
                }
            }
            .padding(12)
            
            Rectangle()
                .fill(self.tokens.hairline)
                .frame(height: 0.75)
                .padding(.horizontal, 12)
            
            // Section 2: 推理强度 (LeiBox Starry Sky Jelly Slider)
            VStack(alignment: .leading, spacing: 10) {
                Text(AppLanguage.text("推理强度", en: "Reasoning Effort"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(self.mutedInk)
                    .padding(.horizontal, 2)
                
                LeiBoxReasoningEffortSlider(
                    effort: self.$reasoningEffort,
                    accent: self.tokens.accent,
                    isDark: self.tokens.isDark
                )
            }
            .padding(14)
        }
        .frame(width: 268)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(self.tokens.card)
                .shadow(
                    color: Color.black.opacity(self.tokens.isDark ? 0.48 : 0.14),
                    radius: 24,
                    x: 0,
                    y: 8
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(self.tokens.hairline, lineWidth: 0.85)
        )
    }
    
    
    private func reloadAvailableModels() {
        let models = AIHotNewsService.availableChatModels()
        self.availableModels = models
        if let current = self.selectedModel, models.contains(current) {
            return
        }
        self.selectedModel = models.first
    }
    
    
    private func editorialStarterRow(
        index: String,
        title: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Text(index)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(self.tokens.accentText)
                    .frame(width: 22, alignment: .leading)
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.90))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(self.mutedInk.opacity(0.75))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .disabled(disabled)
    }
    
    
    private func copyAssistantReply(_ message: NewsChatMessage) {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        self.copiedMessageID = message.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            if self.copiedMessageID == message.id {
                self.copiedMessageID = nil
            }
        }
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
    let secondaryInk: Color
    let mutedInk: Color
    let onSelectItem: (String) -> Void
    
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
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(self.item.resolvedCategory.label)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(self.tokens.accentText)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(self.tokens.positivePillBg, in: Capsule())
                        
                        if !publisher.isEmpty {
                            Text(publisher)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(self.secondaryInk)
                        }
                        
                        if let date = self.item.publishedAt {
                            Text("·")
                                .foregroundStyle(self.mutedInk)
                            Text(DashboardNewsCenterView.relativeTimeString(from: date))
                                .font(.system(size: 12, design: .monospaced).monospacedDigit())
                                .foregroundStyle(self.mutedInk)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .id("article-top")
                    
                    Text(self.item.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if let cover = self.cover {
                        Image(nsImage: cover)
                            .resizable()
                            .interpolation(.medium)
                            .antialiased(true)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                            )
                    }
                    
                    if !self.blocks.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(self.blocks.enumerated()), id: \.offset) { _, block in
                                self.articleBlockView(block)
                            }
                        }
                    } else if !summaryText.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(summaryText)
                                .font(.system(size: self.bodyFontSize, weight: .regular))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.92))
                                .lineSpacing(8)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            
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
                            .foregroundStyle(self.tokens.accentText)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                    
                    if self.previousItem != nil || self.nextItem != nil {
                        Rectangle()
                            .fill(self.tokens.hairline)
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
                .padding(.horizontal, 38)
                .padding(.vertical, 30)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(self.tokens.card)
            .onChange(of: self.item.id) { _, _ in
                readerProxy.scrollTo("article-top", anchor: .top)
            }
        }
    }
    
    
    @ViewBuilder
    private func articleBlockView(_ block: NewsArticleBlock) -> some View {
        switch block {
            case .heading(let level, let text):
                Text(text)
                    .font(.system(size: self.bodyFontSize + (level <= 2 ? 2.5 : 1.0), weight: .semibold))
                    .foregroundStyle(self.tokens.primaryInk)
                    .padding(.top, 4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
            case .paragraph(let text):
                Text(text)
                    .font(.system(size: self.bodyFontSize, weight: .regular))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.90))
                    .lineSpacing(8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
            case .quote(let text):
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(self.tokens.accent)
                        .frame(width: 3)
                    
                    Text(text)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(self.secondaryInk)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                
            case .code(let code):
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(code)
                        .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(self.tokens.primaryInk)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                )
                
            case .list(let items):
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(self.mutedInk)
                                .frame(width: 4.5, height: 4.5)
                                .padding(.top, 8)
                            
                            Text(line)
                                .font(.system(size: self.bodyFontSize, weight: .regular))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.90))
                                .lineSpacing(7)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.leading, 4)
        }
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


// MARK: - Isolated Equatable Chat Bubble & Composer Views

private struct NewsChatBubbleView: View, Equatable {
    
    let message: NewsChatMessage
    let isStreaming: Bool
    let isCopied: Bool
    let effortTitle: String
    let tokens: StudioColorTokens
    let secondaryInk: Color
    let mutedInk: Color
    let onCopy: () -> Void
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message.id == rhs.message.id
            && lhs.message.text == rhs.message.text
            && lhs.isStreaming == rhs.isStreaming
            && lhs.isCopied == rhs.isCopied
            && lhs.effortTitle == rhs.effortTitle
            && lhs.tokens.isDark == rhs.tokens.isDark
    }
    
    var body: some View {
        if self.message.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(self.message.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(self.tokens.primaryInk)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        self.tokens.accent.opacity(self.tokens.isDark ? 0.22 : 0.11),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(self.tokens.accent.opacity(0.22), lineWidth: 0.75)
                    )
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if self.message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && self.isStreaming {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(AppLanguage.text("正在思考（\(self.effortTitle)）…", en: "Thinking (\(self.effortTitle))…"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(self.mutedInk)
                    }
                } else {
                    NewsMarkdownContentView(
                        markdown: self.message.text,
                        isStreaming: self.isStreaming,
                        tokens: self.tokens,
                        secondaryInk: self.secondaryInk,
                        mutedInk: self.mutedInk
                    )
                    
                    if !self.isStreaming {
                        HStack {
                            Spacer(minLength: 0)
                            
                            Button(action: self.onCopy) {
                                HStack(spacing: 4) {
                                    Image(systemName: self.isCopied ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(self.isCopied
                                         ? AppLanguage.text("已复制", en: "Copied")
                                         : AppLanguage.text("复制", en: "Copy"))
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(self.isCopied ? self.tokens.accentText : self.mutedInk)
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(self.tokens.inset, in: Capsule())
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
            )
        }
    }
}


private struct NewsDeepAgentComposerView: View {
    
    let item: AIHotNewsItem
    let hasMessages: Bool
    let isStreaming: Bool
    let activeModelTitle: String
    let effort: NewsReasoningEffort
    let isModelPopoverOpen: Bool
    let tokens: StudioColorTokens
    let secondaryInk: Color
    let mutedInk: Color
    let onTogglePopover: () -> Void
    let onQuickCommentary: () -> Void
    let onQuickImpact: () -> Void
    let onQuickCounterpoint: () -> Void
    let onClearChat: () -> Void
    let onSubmitPrompt: (String) -> Void
    
    @State private var draftText: String = ""
    
    
    private var canSend: Bool {
        !self.isStreaming && !self.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    
    var body: some View {
        let cardRadius: CGFloat = 20
        return VStack(alignment: .leading, spacing: 0) {
            TextField(AppLanguage.text("尽管问…", en: "Ask anything…"), text: self.$draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(self.tokens.primaryInk)
                .lineLimit(1...5)
                .onSubmit {
                    self.submit()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
            
            HStack(spacing: 8) {
                Menu {
                    Button(AppLanguage.text("提炼核心事实与犀利点评", en: "Summarize & Critique"), action: self.onQuickCommentary)
                    Button(AppLanguage.text("对我有什么实际影响？", en: "Practical Impact"), action: self.onQuickImpact)
                    Button(AppLanguage.text("挑刺：水分与反面视角", en: "Counterpoint"), action: self.onQuickCounterpoint)
                    if self.hasMessages {
                        Divider()
                        Button(AppLanguage.text("清空当前对话", en: "Clear Chat"), role: .destructive, action: self.onClearChat)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(self.secondaryInk)
                        .frame(width: 28, height: 28)
                        .background(self.tokens.inset, in: Circle())
                        .contentShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(self.isStreaming)
                .help(AppLanguage.text("快捷指令", en: "Quick Prompts"))
                
                Spacer(minLength: 4)
                
                Button(action: self.onTogglePopover) {
                    HStack(spacing: 5) {
                        Text(self.activeModelTitle)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(self.tokens.primaryInk.opacity(0.86))
                            .lineLimit(1)
                            .frame(maxWidth: 210)
                        
                        Text("·")
                            .foregroundStyle(self.mutedInk)
                        
                        Text(self.effort.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(self.tokens.accentText)
                            .fixedSize(horizontal: true, vertical: false)
                        
                        Image(systemName: self.isModelPopoverOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(self.mutedInk)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        Capsule()
                            .fill(self.isModelPopoverOpen ? self.tokens.insetHover : self.tokens.inset)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(self.isModelPopoverOpen ? self.tokens.accent.opacity(0.45) : self.tokens.hairline, lineWidth: 0.75)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button(action: self.submit) {
                    Image(systemName: self.isStreaming ? "hourglass" : "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(self.canSend ? Color.white : self.mutedInk)
                        .frame(width: 28, height: 28)
                        .background(
                            self.canSend
                                ? (self.tokens.isDark ? self.tokens.accent : Color(red: 0.14, green: 0.15, blue: 0.18))
                                : self.tokens.inset,
                            in: Circle()
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .disabled(!self.canSend)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 11)
        }
        .background(
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(self.tokens.card)
                .shadow(
                    color: Color.black.opacity(self.tokens.isDark ? 0.34 : 0.08),
                    radius: 14,
                    x: 0,
                    y: 4
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .strokeBorder(self.tokens.hairline, lineWidth: 0.85)
        )
        .onChange(of: self.item.id) { _, _ in
            self.draftText = ""
        }
    }
    
    
    private func submit() {
        let prompt = self.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !self.isStreaming else { return }
        self.draftText = ""
        self.onSubmitPrompt(prompt)
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
                    TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: AnimationConstants.isReducedMotionEnabled)) { timeline in
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
        let blocks = NewsMarkdownParser.parse(self.markdown)
        
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                self.renderBlock(block, key: "md-\(idx)")
            }
            
            if self.isStreaming {
                TypewriterStreamingCursor(accent: self.tokens.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    
    @ViewBuilder
    private func renderBlock(_ block: NewsMarkdownBlock, key: String) -> some View {
        switch block {
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
                let isCopied = (self.copiedCodeKey == key)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(language.isEmpty ? "code" : language)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(self.mutedInk)
                        
                        Spacer()
                        
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                            self.copiedCodeKey = key
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1.5))
                                if self.copiedCodeKey == key { self.copiedCodeKey = nil }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 9.5, weight: .semibold))
                                Text(isCopied ? AppLanguage.text("已复制", en: "Copied") : AppLanguage.text("复制代码", en: "Copy"))
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundStyle(isCopied ? self.tokens.accentText : self.mutedInk)
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
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attr = try? AttributedString(markdown: raw, options: options) {
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
    let isRead: Bool
    let hasAIBrief: Bool
    let tokens: StudioColorTokens
    let secondaryInk: Color
    let mutedInk: Color
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.item.title == rhs.item.title
            && lhs.cover === rhs.cover
            && lhs.isRead == rhs.isRead
            && lhs.hasAIBrief == rhs.hasAIBrief
            && lhs.tokens.isDark == rhs.tokens.isDark
    }
    
    
    var body: some View {
        let publisher = self.item.displayPublisherLabel
        let summarySnippet = self.item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        Button(action: self.onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if let cover = self.cover {
                        Color.clear
                            .frame(height: 148)
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
                            .frame(height: 148)
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
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(self.item.title)
                        .font(.system(size: 13.5, weight: self.isRead ? .medium : .semibold))
                        .foregroundStyle(self.isRead ? self.secondaryInk : self.tokens.primaryInk)
                        .lineLimit(2)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                    
                    HStack(spacing: 6) {
                        Text(publisher.isEmpty ? self.item.resolvedCategory.label : publisher)
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
                .padding(12)
            }
            .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        self.isHovered ? self.tokens.accent.opacity(0.45) : self.tokens.hairline,
                        lineWidth: self.isHovered ? 1.0 : 0.8
                    )
            )
            .shadow(color: self.tokens.cardShadow, radius: 4, x: 0, y: 2)
            .offset(y: self.isHovered ? -2 : 0)
            .animation(DashMotion.quick, value: self.isHovered)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering in
            if hovering != self.isHovered {
                self.isHovered = hovering
            }
        }
    }
    
    
    private func editorialCoverTile(summarySnippet: String) -> some View {
        let seed = abs(self.item.id.hashValue)
        let accent: Color = switch seed % 4 {
            case 0: self.tokens.accent
            case 1: self.tokens.secondaryAccent
            case 2: Color(red: 0.212, green: 0.478, blue: 0.612)
            default: self.tokens.heat3
        }
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [accent.opacity(self.tokens.isDark ? 0.30 : 0.18), self.tokens.inset],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            if !summarySnippet.isEmpty {
                Text(summarySnippet)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(self.secondaryInk)
                    .lineLimit(3)
                    .lineSpacing(2.5)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
    }
}
