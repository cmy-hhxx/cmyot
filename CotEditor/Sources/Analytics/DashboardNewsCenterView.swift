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
import WebKit

/// Xiaohongshu-style visual card NEWS workspace with distraction-free reading and a simple
/// AI one-click commentary/summary & follow-up chat with easy one-click reply copying.
struct DashboardNewsCenterView: View {
    
    enum ReaderMode: String, CaseIterable, Identifiable {
        case editorial
        case web
        
        var id: String { self.rawValue }
        
        var label: String {
            switch self {
                case .editorial: AppLanguage.text("阅读", en: "Reader")
                case .web: AppLanguage.text("网页", en: "Web")
            }
        }
    }
    
    @Bindable var newsService: AIHotNewsService
    let tokens: StudioColorTokens
    let initialSelectedID: String?
    let onClose: () -> Void
    var onOpenExcerptDocument: ((String, String) -> Void)?
    
    @State private var selectedCategory: NewsFeedCategory = .all
    @State private var readerMode: ReaderMode = .editorial
    @State private var searchText: String = ""
    @State private var selectedItemID: String?
    @State private var chatInput: String = ""
    @State private var copiedMessageID: String?
    @State private var webProgress: Double = 0
    @State private var webIsLoading: Bool = false
    
    private let bodyFontSize: CGFloat = 15.0
    
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
            self.selectedCategory = self.newsService.selectedCategory
            self.selectedItemID = self.initialSelectedID
            self.syncSelectionSideEffects()
            self.newsService.preloadFeedResources(limit: 20)
        }
        .onChange(of: self.selectedItemID) { _, _ in
            self.chatInput = ""
            self.syncSelectionSideEffects()
        }
        .onKeyPress(.escape) {
            if self.selectedItemID != nil {
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
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
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            if self.selectedItemID == nil {
                HStack(spacing: 2) {
                    ForEach(NewsFeedCategory.allCases) { category in
                        let isActive = (self.selectedCategory == category)
                        Button {
                            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                                self.selectedCategory = category
                                self.newsService.selectedCategory = category
                            }
                        } label: {
                            Text(category == .xSocial ? "X" : category.label)
                                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                                .foregroundStyle(isActive ? self.tokens.onAccentInk : self.secondaryInk)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(
                                    isActive ? self.tokens.accent : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
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
                        .frame(minWidth: 110, maxWidth: 180)
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
                .frame(height: 32)
                .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                )
            } else {
                HStack(spacing: 2) {
                    ForEach(ReaderMode.allCases) { mode in
                        let active = (self.readerMode == mode)
                        Button {
                            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                                self.readerMode = mode
                            }
                        } label: {
                            Text(mode.label)
                                .font(.system(size: 12, weight: active ? .medium : .regular))
                                .foregroundStyle(active ? self.tokens.onAccentInk : self.secondaryInk)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(
                                    active ? self.tokens.accent : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
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
                
                if let url = self.selectedItem?.url {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(self.secondaryInk)
                            .frame(width: 32, height: 32)
                            .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(AppLanguage.text("在浏览器中打开", en: "Open in Browser"))
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
                    .frame(width: 32, height: 32)
                    .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .disabled(self.newsService.isLoading)
            .pointerStyle(.link)
            .help(AppLanguage.text("刷新", en: "Refresh"))
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
    
    
    // MARK: - Xiaohongshu Small-Card Grid Feed
    
    private var xiaohongshuCardGridStage: some View {
        let items = self.displayedItems
        return GeometryReader { geo in
            let colCount: Int = {
                if geo.size.width >= 1040 { return 4 }
                if geo.size.width >= 760 { return 3 }
                return 2
            }()
            let columns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: colCount)
            
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
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
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
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                                    self.selectedItemID = item.id
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
    
    
    // MARK: - Detail Reader + Simple AI Chat Split Stage
    
    private func detailAndChatStage(for item: AIHotNewsItem) -> some View {
        GeometryReader { geo in
            let isCompact = geo.size.width < 820
            if isCompact {
                VStack(spacing: 0) {
                    self.readerPane(for: item)
                        .frame(height: max(220, geo.size.height * 0.54))
                    Rectangle()
                        .fill(self.tokens.hairline)
                        .frame(height: 1)
                    self.aiChatPane(for: item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                let chatWidth = min(420, max(320, floor(geo.size.width * 0.36)))
                HStack(spacing: 0) {
                    self.readerPane(for: item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    Rectangle()
                        .fill(self.tokens.hairline)
                        .frame(width: 1)
                    
                    self.aiChatPane(for: item)
                        .frame(width: chatWidth)
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }
    
    
    // MARK: - Left Reading Pane
    
    private func readerPane(for item: AIHotNewsItem) -> some View {
        VStack(spacing: 0) {
            if self.readerMode == .web && self.webIsLoading {
                GeometryReader { barGeo in
                    Rectangle()
                        .fill(self.tokens.accent)
                        .frame(width: max(16, barGeo.size.width * CGFloat(self.webProgress)), height: 2)
                }
                .frame(height: 2)
            }
            
            if self.readerMode == .web, let webURL = item.url {
                NewsEmbeddedWebView(
                    url: webURL,
                    progress: self.$webProgress,
                    isLoading: self.$webIsLoading
                )
                .id("web-\(item.id)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                self.editorialArticleScroll(for: item)
            }
        }
    }
    
    
    private func editorialArticleScroll(for item: AIHotNewsItem) -> some View {
        let cover = self.newsService.coverImage(for: item)
        let publisher = item.displayPublisherLabel
        let blocks = self.newsService.resolvedArticleBlocks(for: item)
        let summaryText = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isLoadingArticle = self.newsService.loadingArticleIDs.contains(item.id)
            || (blocks.isEmpty && summaryText.isEmpty && !self.newsService.hasFinishedDetailFetch(for: item.id))
        let neighbors = self.adjacentItems
        
        return ScrollViewReader { readerProxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(item.resolvedCategory.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(self.tokens.accentText)
                        
                        if !publisher.isEmpty {
                            Text("·")
                                .foregroundStyle(self.mutedInk)
                            Text(publisher)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(self.secondaryInk)
                        }
                        
                        if let date = item.publishedAt {
                            Text("·")
                                .foregroundStyle(self.mutedInk)
                            Text(Self.relativeTimeString(from: date))
                                .font(.system(size: 12, design: .monospaced).monospacedDigit())
                                .foregroundStyle(self.mutedInk)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .id("article-top")
                    
                    Text(item.title)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if let cover {
                        Image(nsImage: cover)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                            )
                    }
                    
                    if !blocks.isEmpty {
                        VStack(alignment: .leading, spacing: 15) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                                self.articleBlockView(block)
                            }
                        }
                    } else if !summaryText.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(summaryText)
                                .font(.system(size: self.bodyFontSize, weight: .regular))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.90))
                                .lineSpacing(7)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            if isLoadingArticle {
                                self.loadingPlaceholder
                            }
                        }
                    } else if isLoadingArticle {
                        self.loadingPlaceholder
                    } else if let url = item.url {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(spacing: 6) {
                                Text(AppLanguage.text("阅读原文", en: "Read Original Article"))
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
                    
                    if neighbors.previous != nil || neighbors.next != nil {
                        Rectangle()
                            .fill(self.tokens.hairline)
                            .frame(height: 1)
                            .padding(.top, 6)
                        
                        HStack(spacing: 12) {
                            if let prev = neighbors.previous {
                                self.neighborButton(prev, isNext: false) {
                                    self.selectedItemID = prev.id
                                    readerProxy.scrollTo("article-top", anchor: .top)
                                }
                            } else {
                                Spacer(minLength: 0).frame(maxWidth: .infinity)
                            }
                            
                            if let next = neighbors.next {
                                self.neighborButton(next, isNext: true) {
                                    self.selectedItemID = next.id
                                    readerProxy.scrollTo("article-top", anchor: .top)
                                }
                            } else {
                                Spacer(minLength: 0).frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 720, alignment: .leading)
                .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                )
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .onChange(of: item.id) { _, _ in
                readerProxy.scrollTo("article-top", anchor: .top)
            }
        }
    }
    
    
    // MARK: - Right Simple AI Commentary & Follow-Up Chat Pane
    
    private func aiChatPane(for item: AIHotNewsItem) -> some View {
        let messages = self.newsService.chatMessages(for: item)
        let isStreaming = (self.newsService.streamingChatItemID == item.id)
        
        return VStack(spacing: 0) {
            // Chat Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(self.tokens.accent)
                
                Text(AppLanguage.text("AI 点评 & 追问", en: "AI Chat"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(self.tokens.primaryInk)
                
                Spacer(minLength: 4)
                
                Button {
                    Task {
                        await self.newsService.requestAICommentary(for: item)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(AppLanguage.text("一键点评总结", en: "Summarize"))
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(self.tokens.onAccentInk)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(self.tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .disabled(isStreaming)
                
                if !messages.isEmpty {
                    Button {
                        self.newsService.clearChat(for: item.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(self.mutedInk)
                            .frame(width: 26, height: 26)
                            .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .disabled(isStreaming)
                    .help(AppLanguage.text("清空对话", en: "Clear Chat"))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            
            Rectangle()
                .fill(self.tokens.hairline)
                .frame(height: 1)
            
            // Messages List
            ScrollViewReader { chatProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    if messages.isEmpty {
                        VStack(spacing: 14) {
                            Spacer(minLength: 28)
                            
                            Button {
                                Task {
                                    await self.newsService.requestAICommentary(for: item)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 12.5, weight: .semibold))
                                    Text(AppLanguage.text("AI 一键点评总结", en: "AI Summary & Commentary"))
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(self.tokens.onAccentInk)
                                .padding(.horizontal, 18)
                                .frame(height: 36)
                                .background(self.tokens.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            .disabled(isStreaming)
                            
                            VStack(spacing: 8) {
                                ForEach([
                                    "用大白话 3 句话讲清楚核心干货",
                                    "这事对普通开发者/创作者有什么实际影响？",
                                    "有没有什么坑或反面观点？",
                                ], id: \.self) { prompt in
                                    Button {
                                        Task {
                                            await self.newsService.sendChatFollowUp(prompt, for: item)
                                        }
                                    } label: {
                                        Text(prompt)
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundStyle(self.secondaryInk)
                                            .lineLimit(1)
                                            .padding(.horizontal, 12)
                                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                                            .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .pointerStyle(.link)
                                    .disabled(isStreaming)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { msg in
                                self.chatBubble(msg, isStreaming: isStreaming && msg.id == messages.last?.id)
                                    .id(msg.id)
                            }
                        }
                        .padding(14)
                    }
                    
                    if let err = self.newsService.chatErrorMessage, !err.isEmpty {
                        Text(err)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .onChange(of: messages.last?.text ?? "") { _, _ in
                    if let lastID = messages.last?.id {
                        chatProxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            
            Rectangle()
                .fill(self.tokens.hairline)
                .frame(height: 1)
            
            // Simple Follow-Up Chat Input
            HStack(spacing: 8) {
                TextField(AppLanguage.text("追问这篇文章…", en: "Ask a follow-up…"), text: self.$chatInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(self.tokens.primaryInk)
                    .onSubmit {
                        self.submitChatFollowUp(for: item)
                    }
                
                Button {
                    self.submitChatFollowUp(for: item)
                } label: {
                    Image(systemName: isStreaming ? "hourglass" : "arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(self.tokens.onAccentInk)
                        .frame(width: 28, height: 28)
                        .background(
                            self.canSendFollowUp(isStreaming: isStreaming) ? self.tokens.accent : self.mutedInk.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .disabled(!self.canSendFollowUp(isStreaming: isStreaming))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(self.tokens.hairlineStrong, lineWidth: 0.8)
            )
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(self.tokens.canvasTop)
    }
    
    
    @ViewBuilder
    private func chatBubble(_ message: NewsChatMessage, isStreaming: Bool) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 28)
                Text(message.text)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(self.tokens.onAccentInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(self.tokens.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .textSelection(.enabled)
            }
        } else {
            let isCopied = (self.copiedMessageID == message.id)
            VStack(alignment: .leading, spacing: 8) {
                if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isStreaming {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(AppLanguage.text("AI 正在思考…", en: "Thinking…"))
                            .font(.system(size: 12))
                            .foregroundStyle(self.mutedInk)
                    }
                } else {
                    Text(message.text)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(self.tokens.primaryInk.opacity(0.92))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack {
                        Spacer(minLength: 0)
                        
                        Button {
                            self.copyAssistantReply(message)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10.5, weight: .semibold))
                                Text(isCopied
                                     ? AppLanguage.text("已复制", en: "Copied")
                                     : AppLanguage.text("复制回复", en: "Copy"))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(isCopied ? self.tokens.accentText : self.secondaryInk)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
            )
        }
    }
    
    
    private func canSendFollowUp(isStreaming: Bool) -> Bool {
        !isStreaming && !self.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    
    private func submitChatFollowUp(for item: AIHotNewsItem) {
        let prompt = self.chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, self.newsService.streamingChatItemID == nil else { return }
        self.chatInput = ""
        Task {
            await self.newsService.sendChatFollowUp(prompt, for: item)
        }
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
    
    
    // MARK: - Article Blocks & Helpers
    
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
                    .lineSpacing(7)
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
                        .lineSpacing(5)
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
                                .lineSpacing(6)
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
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
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


// MARK: - Xiaohongshu-Style Visual News Card

private struct XiaohongshuNewsCard: View {
    
    let item: AIHotNewsItem
    let cover: NSImage?
    let isRead: Bool
    let hasAIBrief: Bool
    let tokens: StudioColorTokens
    let secondaryInk: Color
    let mutedInk: Color
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        let publisher = self.item.displayPublisherLabel
        let summarySnippet = self.item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        Button(action: self.onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if let cover = self.cover {
                        GeometryReader { geo in
                            Image(nsImage: cover)
                                .resizable()
                                .interpolation(.high)
                                .antialiased(true)
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        }
                        .frame(height: 148)
                    } else {
                        self.editorialCoverTile(summarySnippet: summarySnippet)
                            .frame(height: 124)
                    }
                    
                    HStack {
                        Text(self.item.resolvedCategory.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(self.tokens.primaryInk)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(self.tokens.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        
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
                    .padding(8)
                }
                .frame(maxWidth: .infinity)
                .clipped()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(self.item.title)
                        .font(.system(size: 13.5, weight: self.isRead ? .medium : .semibold))
                        .foregroundStyle(self.isRead ? self.secondaryInk : self.tokens.primaryInk)
                        .lineLimit(2)
                        .lineSpacing(2.5)
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
            .shadow(color: self.tokens.cardShadow, radius: self.isHovered ? 10 : 5, x: 0, y: self.isHovered ? 4 : 2)
            .scaleEffect(self.isHovered ? 1.012 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.80), value: self.isHovered)
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


// MARK: - Embedded WebKit Original-Page View

private struct NewsEmbeddedWebView: NSViewRepresentable {
    
    let url: URL
    @Binding var progress: Double
    @Binding var isLoading: Bool
    
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.observe(webView)
        webView.load(URLRequest(url: self.url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15))
        return webView
    }
    
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if webView.url?.absoluteString != self.url.absoluteString, !webView.isLoading {
            webView.load(URLRequest(url: self.url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15))
        }
    }
    
    
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        
        var parent: NewsEmbeddedWebView
        private var progressObservation: NSKeyValueObservation?
        private var loadingObservation: NSKeyValueObservation?
        
        init(parent: NewsEmbeddedWebView) {
            self.parent = parent
        }
        
        func observe(_ webView: WKWebView) {
            self.progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                let val = view.estimatedProgress
                Task { @MainActor [weak self] in
                    self?.parent.progress = val
                }
            }
            self.loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                let loading = view.isLoading
                Task { @MainActor [weak self] in
                    self?.parent.isLoading = loading
                }
            }
        }
    }
}
