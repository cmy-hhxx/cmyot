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

/// Focused, distraction-free NEWS reader inside the Analytics Dashboard.
/// Keeps a single quiet top bar, a scannable left headline list, and a clean right reading pane.
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
    @State private var webProgress: Double = 0
    @State private var webIsLoading: Bool = false
    
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
        if let id = self.selectedItemID,
           let match = self.displayedItems.first(where: { $0.id == id })
            ?? self.newsService.items.first(where: { $0.id == id })
        {
            return match
        }
        return self.displayedItems.first
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
            
            GeometryReader { geo in
                let compactWidth = geo.size.width < 760
                if compactWidth {
                    VStack(spacing: 0) {
                        self.feedListPane
                            .frame(height: max(180, floor(geo.size.height * 0.38)))
                        Rectangle()
                            .fill(self.tokens.hairline)
                            .frame(height: 1)
                        self.readerPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    let listWidth = min(360, max(300, floor(geo.size.width * 0.32)))
                    HStack(spacing: 0) {
                        self.feedListPane
                            .frame(width: listWidth)
                        
                        Rectangle()
                            .fill(self.tokens.hairline)
                            .frame(width: 1)
                        
                        self.readerPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(self.tokens.canvasTop)
        .onAppear {
            self.selectedCategory = self.newsService.selectedCategory
            if let initialSelectedID {
                self.selectedItemID = initialSelectedID
            } else if self.selectedItemID == nil {
                self.selectedItemID = self.displayedItems.first?.id
            }
            self.syncSelectionSideEffects()
            self.newsService.preloadFeedResources(limit: 16)
        }
        .onChange(of: self.selectedItemID) { _, _ in
            self.syncSelectionSideEffects()
        }
        .onKeyPress(.upArrow) {
            self.stepSelection(by: -1)
        }
        .onKeyPress(.downArrow) {
            self.stepSelection(by: 1)
        }
    }
    
    
    // MARK: - Single Quiet Top Bar
    
    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: self.onClose) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(AppLanguage.text("返回", en: "Back"))
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
            
            HStack(spacing: 2) {
                ForEach(NewsFeedCategory.allCases) { category in
                    let isActive = (self.selectedCategory == category)
                    Button {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                            self.selectedCategory = category
                            self.newsService.selectedCategory = category
                            if let first = self.displayedItems.first {
                                self.selectedItemID = first.id
                            }
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
            
            Spacer(minLength: 8)
            
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(self.mutedInk)
                TextField(AppLanguage.text("搜索", en: "Search"), text: self.$searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(self.tokens.primaryInk)
                    .frame(minWidth: 96, maxWidth: 168)
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
    
    
    // MARK: - Left Scannable Headline List
    
    private var feedListPane: some View {
        let items = self.displayedItems
        return Group {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(self.mutedInk.opacity(0.6))
                    Text(AppLanguage.text("暂无匹配资讯", en: "No articles"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(self.mutedInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 4) {
                            ForEach(items) { item in
                                self.headlineRow(item)
                                    .id(item.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: self.selectedItemID) { _, nextID in
                        guard let nextID else { return }
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                            scrollProxy.scrollTo(nextID, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(self.tokens.canvasTop)
    }
    
    
    private func headlineRow(_ item: AIHotNewsItem) -> some View {
        let isSelected = (self.selectedItem?.id == item.id)
        let isRead = self.newsService.isRead(item)
        let publisher = item.displayPublisherLabel
        
        return Button {
            self.selectedItemID = item.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(isRead ? Color.clear : self.tokens.accent)
                    .frame(width: 5, height: 5)
                    .padding(.top, 6.5)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13.5, weight: isSelected || !isRead ? .medium : .regular))
                        .foregroundStyle(isSelected ? self.tokens.primaryInk : (isRead ? self.secondaryInk : self.tokens.primaryInk))
                        .lineLimit(2)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack(spacing: 8) {
                        Text(publisher.isEmpty ? item.resolvedCategory.label : publisher)
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundStyle(self.mutedInk)
                            .lineLimit(1)
                        
                        if let date = item.publishedAt {
                            Text(Self.relativeTimeString(from: date))
                                .font(.system(size: 11, design: .monospaced).monospacedDigit())
                                .foregroundStyle(self.mutedInk)
                        }
                        
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? self.tokens.card : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? self.tokens.hairlineStrong : Color.clear, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    // MARK: - Right Distraction-Free Reader
    
    @ViewBuilder
    private var readerPane: some View {
        if let item = self.selectedItem {
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
        } else {
            VStack {
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(self.mutedInk.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                VStack(alignment: .leading, spacing: 20) {
                    // Metadata line
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
                    
                    // Title
                    Text(item.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Optional cover image
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
                    
                    // Body blocks or excerpt
                    if !blocks.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                                self.articleBlockView(block)
                            }
                        }
                    } else if !summaryText.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
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
                    
                    // Quiet Previous / Next article navigation
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
                                Spacer(minLength: 0)
                                    .frame(maxWidth: .infinity)
                            }
                            
                            if let next = neighbors.next {
                                self.neighborButton(next, isNext: true) {
                                    self.selectedItemID = next.id
                                    readerProxy.scrollTo("article-top", anchor: .top)
                                }
                            } else {
                                Spacer(minLength: 0)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(32)
                .frame(maxWidth: 720, alignment: .leading)
                .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                )
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .onChange(of: item.id) { _, _ in
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
                    .lineSpacing(7)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
            case .quote(let text):
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(self.tokens.accent)
                        .frame(width: 3)
                    
                    Text(text)
                        .font(.system(size: 14.5, weight: .regular))
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
    
    
    // MARK: - Helpers
    
    private func syncSelectionSideEffects() {
        guard let item = self.selectedItem else { return }
        if self.selectedItemID != item.id {
            self.selectedItemID = item.id
        }
        self.newsService.markRead(item)
        Task {
            await self.newsService.fetchArticleExcerptIfNeeded(for: item)
        }
    }
    
    
    private func stepSelection(by delta: Int) -> KeyPress.Result {
        let items = self.displayedItems
        guard !items.isEmpty else { return .ignored }
        let currentIndex = items.firstIndex(where: { $0.id == self.selectedItem?.id }) ?? 0
        let nextIndex = min(max(0, currentIndex + delta), items.count - 1)
        self.selectedItemID = items[nextIndex].id
        return .handled
    }
    
    
    private static func relativeTimeString(from date: Date) -> String {
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
