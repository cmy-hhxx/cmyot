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
    let onClose: () -> Void
    var onOpenExcerptDocument: ((String, String) -> Void)?
    
    @State private var selectedCategory: NewsFeedCategory = .all
    @State private var searchText: String = ""
    @State private var selectedItemID: String?
    @State private var chatInput: String = ""
    @State private var reasoningEffort: NewsReasoningEffort = .balanced
    @State private var copiedMessageID: String?
    
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
                                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? self.tokens.onAccentInk : self.secondaryInk)
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                                .background(
                                    isActive ? self.tokens.accent : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
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
            } else if let url = self.selectedItem?.url {
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
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                                    self.selectedItemID = item.id
                                }
                            }
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
        GeometryReader { geo in
            let isCompact = geo.size.width < 840
            if isCompact {
                VStack(spacing: 0) {
                    self.editorialArticleScroll(for: item)
                        .frame(height: max(220, geo.size.height * 0.50))
                    Rectangle()
                        .fill(self.tokens.hairline)
                        .frame(height: 1)
                    self.aiChatPane(for: item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // Golden ~58 / 42 balanced split so neither article nor chat feels squished or overly wide
                let chatWidth = min(480, max(370, floor(geo.size.width * 0.41)))
                HStack(spacing: 0) {
                    self.editorialArticleScroll(for: item)
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
    
    
    // MARK: - Native Editorial Reading Pane (Zero Embedded WebView)
    
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
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(item.resolvedCategory.label)
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
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if let cover {
                        Image(nsImage: cover)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                            )
                    }
                    
                    if !blocks.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                                self.articleBlockView(block)
                            }
                        }
                    } else if !summaryText.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(summaryText)
                                .font(.system(size: self.bodyFontSize, weight: .regular))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.92))
                                .lineSpacing(7.5)
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
                    
                    if neighbors.previous != nil || neighbors.next != nil {
                        Rectangle()
                            .fill(self.tokens.hairline)
                            .frame(height: 1)
                            .padding(.top, 8)
                        
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
                .padding(.horizontal, 34)
                .padding(.vertical, 28)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(self.tokens.card)
            .onChange(of: item.id) { _, _ in
                readerProxy.scrollTo("article-top", anchor: .top)
            }
        }
    }
    
    
    // MARK: - Right AI Chat Pane + LeiBox Reasoning Effort Slider
    
    private func aiChatPane(for item: AIHotNewsItem) -> some View {
        let messages = self.newsService.chatMessages(for: item)
        let isStreaming = (self.newsService.streamingChatItemID == item.id)
        
        return VStack(spacing: 0) {
            // Minimal Chat Header (no duplicate summarize button!)
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(self.tokens.accent)
                
                Text(AppLanguage.text("AI 讨论与解读", en: "AI Discussion"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(self.tokens.primaryInk)
                
                Spacer(minLength: 4)
                
                if !messages.isEmpty {
                    Button {
                        self.newsService.clearChat(for: item.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10.5, weight: .medium))
                            Text(AppLanguage.text("清空", en: "Clear"))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(self.mutedInk)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .disabled(isStreaming)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            
            Rectangle()
                .fill(self.tokens.hairline)
                .frame(height: 1)
            
            // Messages Stream
            ScrollViewReader { chatProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    if messages.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Spacer(minLength: 20)
                            
                            // Single clear summarize entry + 2 distinct follow-up angles (zero duplicate styles)
                            Button {
                                Task {
                                    await self.newsService.requestAICommentary(for: item, effort: self.reasoningEffort)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(AppLanguage.text("总结要点 & 犀利点评", en: "Summarize & Critique"))
                                        .font(.system(size: 13, weight: .semibold))
                                    Spacer()
                                    Text(self.reasoningEffort.title)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.20), in: Capsule())
                                }
                                .foregroundStyle(self.tokens.onAccentInk)
                                .padding(.horizontal, 14)
                                .frame(height: 40)
                                .background(self.tokens.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            .disabled(isStreaming)
                            
                            HStack(spacing: 8) {
                                self.distinctAngleChip(
                                    title: AppLanguage.text("对我有什么用？", en: "Impact on Me"),
                                    prompt: "结合一线开发者和创作者视角，这件事有什么直接影响或能立刻用上的机会？",
                                    item: item,
                                    disabled: isStreaming
                                )
                                
                                self.distinctAngleChip(
                                    title: AppLanguage.text("挑刺 & 反面观点", en: "Counterpoint"),
                                    prompt: "别光说好话，帮我挑挑这件事背后的水分、风险或反面观点。",
                                    item: item,
                                    disabled: isStreaming
                                )
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(messages) { msg in
                                self.chatBubble(msg, isStreaming: isStreaming && msg.id == messages.last?.id)
                                    .id(msg.id)
                            }
                        }
                        .padding(16)
                    }
                    
                    if let err = self.newsService.chatErrorMessage, !err.isEmpty {
                        Text(err)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
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
            
            // Polished Composer Dock with integrated LeiBox Reasoning Effort Slider
            VStack(spacing: 10) {
                LeiBoxReasoningEffortSlider(
                    effort: self.$reasoningEffort,
                    accent: self.tokens.accent,
                    isDark: self.tokens.isDark
                )
                
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(AppLanguage.text("继续追问任何细节…", en: "Ask a follow-up…"), text: self.$chatInput, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineLimit(1...4)
                        .onSubmit {
                            self.submitChatFollowUp(for: item)
                        }
                    
                    Button {
                        self.submitChatFollowUp(for: item)
                    } label: {
                        Image(systemName: isStreaming ? "hourglass" : "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(self.tokens.onAccentInk)
                            .frame(width: 28, height: 28)
                            .background(
                                self.canSendFollowUp(isStreaming: isStreaming) ? self.tokens.accent : self.mutedInk.opacity(0.32),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .disabled(!self.canSendFollowUp(isStreaming: isStreaming))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(self.tokens.hairlineStrong, lineWidth: 0.9)
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .background(
                self.tokens.canvasTop
                    .overlay(alignment: .top) {
                        Rectangle().fill(self.tokens.hairline).frame(height: 1)
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(self.tokens.canvasTop)
    }
    
    
    private func distinctAngleChip(
        title: String,
        prompt: String,
        item: AIHotNewsItem,
        disabled: Bool
    ) -> some View {
        Button {
            Task {
                await self.newsService.sendChatFollowUp(
                    prompt,
                    for: item,
                    displayUserText: title,
                    effort: self.reasoningEffort
                )
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(self.secondaryInk)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .disabled(disabled)
    }
    
    
    @ViewBuilder
    private func chatBubble(_ message: NewsChatMessage, isStreaming: Bool) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 36)
                Text(message.text)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(self.tokens.onAccentInk)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8.5)
                    .background(self.tokens.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .textSelection(.enabled)
            }
        } else {
            let isCopied = (self.copiedMessageID == message.id)
            VStack(alignment: .leading, spacing: 10) {
                if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isStreaming {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text(AppLanguage.text("AI 正在思考…", en: "Thinking…"))
                            .font(.system(size: 12))
                            .foregroundStyle(self.mutedInk)
                    }
                } else {
                    Text(message.text)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(self.tokens.primaryInk.opacity(0.92))
                        .lineSpacing(5.5)
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
                            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
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
            await self.newsService.sendChatFollowUp(prompt, for: item, effort: self.reasoningEffort)
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
                    .lineSpacing(7.5)
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
                        .lineSpacing(5.5)
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
                                .lineSpacing(6.5)
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
        let trackBg = self.isDark ? Color.white.opacity(0.065) : Color.black.opacity(0.055)
        let border = self.isDark ? Color.white.opacity(0.11) : Color.black.opacity(0.08)
        let stretch = min(0.24, abs(self.jellyVelocity) * 0.012)
        let scaleX: CGFloat = 1.0 + stretch
        let scaleY: CGFloat = max(0.82, 1.0 - stretch * 0.58)
        
        VStack(spacing: 5) {
            GeometryReader { geo in
                let w = max(120, geo.size.width)
                let h = geo.size.height
                let pad: CGFloat = 4
                let thumbW: CGFloat = max(62, (w - pad * 2) / 3.0)
                let travelW = max(1, w - pad * 2 - thumbW)
                let clampedP = max(0, min(1, self.normalizedProgress))
                let thumbX = pad + clampedP * travelW
                let fillWidth = max(thumbW + pad, thumbX + thumbW * 0.85)
                
                ZStack(alignment: .leading) {
                    // Base recessed pill track
                    Capsule()
                        .fill(trackBg)
                    
                    // Glowing active track with animated flowing star field
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
                                        self.accent.opacity(self.isDark ? 0.34 : 0.24),
                                        self.accent.opacity(self.isDark ? 0.62 : 0.44),
                                    ]),
                                    startPoint: .zero,
                                    endPoint: CGPoint(x: activeRect.width, y: 0)
                                )
                            )
                            
                            ctx.drawLayer { layer in
                                layer.clip(to: activePath)
                                for star in Self.stars {
                                    let drift = (star.x + CGFloat(t) * star.speed * speedBoost).truncatingRemainder(dividingBy: 1.0)
                                    let sx = drift * size.width
                                    let sy = star.y * size.height
                                    let twinkle = 0.42 + 0.58 * (0.5 + 0.5 * sin(t * 2.6 + star.phase))
                                    let r = star.size * 0.5
                                    layer.fill(
                                        Circle().path(in: CGRect(x: sx - r, y: sy - r, width: star.size, height: star.size)),
                                        with: .color(Color.white.opacity(twinkle * (self.isDark ? 0.82 : 0.90)))
                                    )
                                }
                            }
                        }
                    }
                    .clipShape(Capsule())
                    .allowsHitTesting(false)
                    
                    // Three discrete stop tick dots
                    HStack {
                        ForEach(NewsReasoningEffort.allCases) { stop in
                            Spacer(minLength: 0)
                            Circle()
                                .fill(stop.rawValue <= self.effort.rawValue ? Color.white.opacity(0.65) : Color.primary.opacity(0.18))
                                .frame(width: 3.5, height: 3.5)
                            Spacer(minLength: 0)
                        }
                    }
                    .allowsHitTesting(false)
                    
                    // Velocity-driven jelly thumb capsule
                    Capsule()
                        .fill(self.accent)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.42), lineWidth: 0.9)
                        )
                        .shadow(color: self.accent.opacity(0.35), radius: self.isDragging ? 8 : 5, y: 2)
                        .overlay {
                            HStack(spacing: 4) {
                                Image(systemName: self.effort == .deep ? "sparkles" : (self.effort == .balanced ? "bolt.fill" : "hare.fill"))
                                    .font(.system(size: 9.5, weight: .bold))
                                Text(self.effort.title)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(Color.white)
                        }
                        .frame(width: thumbW, height: h - pad * 2)
                        .scaleEffect(x: scaleX, y: scaleY, anchor: .center)
                        .offset(x: thumbX)
                        .allowsHitTesting(false)
                    
                    // Invisible tap/click targets for the 3 stops
                    HStack(spacing: 0) {
                        ForEach(NewsReasoningEffort.allCases) { stop in
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    self.snap(to: stop, impulse: stop.rawValue > self.effort.rawValue ? 12 : -12)
                                }
                        }
                    }
                }
                .overlay(
                    Capsule()
                        .strokeBorder(border, lineWidth: 0.8)
                        .allowsHitTesting(false)
                )
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            self.isDragging = true
                            let rawP = (value.location.x - pad - thumbW * 0.5) / travelW
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
                            let rawP = (value.location.x - pad - thumbW * 0.5) / travelW
                            let clamped = max(0, min(1, rawP))
                            let nearestIdx = min(2, max(0, Int((clamped * 2.0).rounded())))
                            let stop = NewsReasoningEffort(rawValue: nearestIdx) ?? .balanced
                            self.snap(to: stop, impulse: 0)
                        }
                )
                .pointerStyle(.link)
            }
            .frame(height: 30)
            
            HStack {
                ForEach(NewsReasoningEffort.allCases) { stop in
                    let active = (self.effort == stop)
                    Button {
                        self.snap(to: stop, impulse: stop.rawValue > self.effort.rawValue ? 12 : -12)
                    } label: {
                        Text(stop.title)
                            .font(.system(size: 10, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? self.accent : Color.secondary.opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
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
                        .frame(height: 152)
                    } else {
                        self.editorialCoverTile(summarySnippet: summarySnippet)
                            .frame(height: 132)
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
