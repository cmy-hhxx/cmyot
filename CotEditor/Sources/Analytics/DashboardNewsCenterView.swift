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

/// Interactive Readwise/Perplexity-inspired full NEWS workspace embedded inside the Analytics Dashboard.
struct DashboardNewsCenterView: View {
    
    enum FeedFilter: Hashable, Identifiable {
        case category(NewsFeedCategory)
        case saved
        
        var id: String {
            switch self {
                case .category(let cat): "cat:\(cat.rawValue)"
                case .saved: "saved"
            }
        }
        
        var label: String {
            switch self {
                case .category(let cat): cat.label
                case .saved: AppLanguage.text("收藏", en: "Saved")
            }
        }
    }
    
    enum SortOrder: String, CaseIterable, Identifiable {
        case signal
        case latest
        case heat
        
        var id: String { self.rawValue }
        
        var label: String {
            switch self {
                case .signal: AppLanguage.text("精选信号", en: "Top Signal")
                case .latest: AppLanguage.text("最新发布", en: "Latest")
                case .heat: AppLanguage.text("热度优先", en: "Hottest")
            }
        }
    }
    
    enum FeedLayoutMode: String, CaseIterable, Identifiable {
        case cards
        case list
        
        var id: String { self.rawValue }
        
        var icon: String {
            switch self {
                case .cards: "square.grid.2x2"
                case .list: "list.bullet"
            }
        }
        
        var label: String {
            switch self {
                case .cards: AppLanguage.text("画报", en: "Cards")
                case .list: AppLanguage.text("列表", en: "List")
            }
        }
    }
    
    @Bindable var newsService: AIHotNewsService
    let tokens: StudioColorTokens
    let initialSelectedID: String?
    let onClose: () -> Void
    var onOpenExcerptDocument: ((String, String) -> Void)?
    
    @State private var activeFilter: FeedFilter = .category(.all)
    @State private var sortOrder: SortOrder = .signal
    @State private var layoutMode: FeedLayoutMode = .cards
    @State private var searchText: String = ""
    @State private var selectedItemID: String?
    @State private var noteDraft: String = ""
    @State private var statusToast: String?
    
    
    private var displayedItems: [AIHotNewsItem] {
        let base: [AIHotNewsItem] = switch self.activeFilter {
            case .category(let category):
                category == .all
                    ? self.newsService.items
                    : self.newsService.items.filter { $0.resolvedCategory == category }
            case .saved:
                self.newsService.savedBookmarkedItems
        }
        
        let query = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searched = query.isEmpty ? base : base.filter { item in
            item.title.lowercased().contains(query)
                || item.displayPublisherLabel.lowercased().contains(query)
                || (item.tag?.lowercased().contains(query) ?? false)
                || (item.summary?.lowercased().contains(query) ?? false)
        }
        
        switch self.sortOrder {
            case .signal:
                return searched
            case .latest:
                return searched.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            case .heat:
                return searched.sorted { ($0.heatScore ?? -1) > ($1.heatScore ?? -1) }
        }
    }
    
    private var selectedItem: AIHotNewsItem? {
        if let id = self.selectedItemID,
           let match = self.displayedItems.first(where: { $0.id == id })
            ?? self.newsService.items.first(where: { $0.id == id })
            ?? self.newsService.savedBookmarkedItems.first(where: { $0.id == id })
        {
            return match
        }
        return self.displayedItems.first
    }
    
    
    var body: some View {
        VStack(spacing: 0) {
            self.topToolbar
            
            Rectangle()
                .fill(self.tokens.hairline)
                .frame(height: 0.75)
            
            GeometryReader { geo in
                let compactWidth = geo.size.width < 760
                if compactWidth {
                    VStack(spacing: 0) {
                        self.feedPane(isCompact: true)
                            .frame(height: max(200, geo.size.height * 0.46))
                        Rectangle()
                            .fill(self.tokens.hairline)
                            .frame(height: 0.75)
                        self.readerPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    let feedW = max(310, min(460, geo.size.width * 0.44))
                    HStack(spacing: 0) {
                        self.feedPane(isCompact: false)
                            .frame(width: feedW)
                        Rectangle()
                            .fill(self.tokens.hairline)
                            .frame(width: 0.75)
                        self.readerPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(
            LinearGradient(
                colors: [self.tokens.canvasTop, self.tokens.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            if let initialSelectedID {
                self.selectedItemID = initialSelectedID
            } else if self.selectedItemID == nil {
                self.selectedItemID = self.displayedItems.first?.id
            }
            self.syncSelectionSideEffects()
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
    
    
    // MARK: Top Toolbar
    
    private var topToolbar: some View {
        HStack(spacing: 10) {
            Button(action: self.onClose) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(AppLanguage.text("返回看板", en: "Back to Dashboard"))
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(self.tokens.primaryInk.opacity(0.84))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
                )
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            // Category pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(NewsFeedCategory.allCases) { category in
                        self.filterPill(.category(category))
                    }
                    self.filterPill(.saved, count: self.newsService.bookmarkedIDs.count)
                }
            }
            .frame(maxWidth: 360)
            
            Spacer(minLength: 8)
            
            // Search box
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.45))
                TextField(AppLanguage.text("搜索标题、来源或关键词", en: "Search"), text: self.$searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(self.tokens.primaryInk)
                    .frame(minWidth: 120, maxWidth: 190)
                if !self.searchText.isEmpty {
                    Button {
                        self.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(self.tokens.primaryInk.opacity(0.42))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
            )
            
            // Sort picker
            Menu {
                ForEach(SortOrder.allCases) { order in
                    Button {
                        self.sortOrder = order
                    } label: {
                        HStack {
                            Text(order.label)
                            if self.sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 10.5, weight: .medium))
                    Text(self.sortOrder.label)
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(self.tokens.primaryInk.opacity(0.78))
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            // Layout switcher
            HStack(spacing: 2) {
                ForEach(FeedLayoutMode.allCases) { mode in
                    let active = (self.layoutMode == mode)
                    Button {
                        withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.16)) {
                            self.layoutMode = mode
                        }
                    } label: {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(active ? self.tokens.onAccentInk : self.tokens.primaryInk.opacity(0.62))
                            .frame(width: 26, height: 24)
                            .background(active ? self.tokens.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(mode.label)
                }
            }
            .padding(3)
            .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
            )
            
            Button {
                Task {
                    await self.newsService.refreshIfNeeded(force: true)
                }
            } label: {
                Image(systemName: self.newsService.isLoading ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.75))
                    .frame(width: 30, height: 30)
                    .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
                    )
            }
            .buttonStyle(.plain)
            .disabled(self.newsService.isLoading)
            .help(AppLanguage.text("刷新资讯", en: "Refresh"))
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }
    
    
    @ViewBuilder
    private func filterPill(_ filter: FeedFilter, count: Int? = nil) -> some View {
        let isActive = (self.activeFilter == filter)
        Button {
            withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.16)) {
                self.activeFilter = filter
                if let first = self.displayedItems.first {
                    self.selectedItemID = first.id
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(filter.label)
                    .font(.system(size: 11.5, weight: isActive ? .semibold : .medium))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .opacity(0.78)
                }
            }
            .foregroundStyle(isActive ? self.tokens.onAccentInk : self.tokens.primaryInk.opacity(0.72))
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(isActive ? self.tokens.accent : self.tokens.inset, in: Capsule())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    // MARK: Feed Pane
    
    private func feedPane(isCompact: Bool) -> some View {
        let items = self.displayedItems
        return Group {
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: self.activeFilter == .saved ? "bookmark" : "newspaper")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(self.tokens.primaryInk.opacity(0.32))
                    Text(
                        self.activeFilter == .saved
                            ? AppLanguage.text("暂无收藏的资讯", en: "No saved stories yet")
                            : AppLanguage.text("没有匹配的资讯内容", en: "No matching stories")
                    )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.62))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    if self.layoutMode == .cards && !isCompact {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                            spacing: 10
                        ) {
                            ForEach(items) { item in
                                self.gridCard(item)
                            }
                        }
                        .padding(14)
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(items) { item in
                                self.listRow(item)
                            }
                        }
                        .padding(12)
                    }
                }
            }
        }
    }
    
    
    private func gridCard(_ item: AIHotNewsItem) -> some View {
        let isSelected = (self.selectedItem?.id == item.id)
        let isRead = self.newsService.isRead(item)
        let isSaved = self.newsService.isBookmarked(item)
        let cover = self.newsService.coverImage(for: item)
        let publisher = item.displayPublisherLabel
        
        return Button {
            self.selectedItemID = item.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    if let cover {
                        GeometryReader { geo in
                            Image(nsImage: cover)
                                .resizable()
                                .interpolation(.medium)
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        }
                        .frame(height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(self.tokens.inset)
                            .frame(height: 82)
                            .overlay(
                                VStack(spacing: 3) {
                                    Text(item.resolvedCategory.badgeLabel.isEmpty ? "AI" : item.resolvedCategory.badgeLabel)
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(self.tokens.accentText)
                                    if !publisher.isEmpty {
                                        Text(publisher)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(self.tokens.primaryInk.opacity(0.45))
                                            .lineLimit(1)
                                            .padding(.horizontal, 8)
                                    }
                                }
                            )
                    }
                    
                    Button {
                        self.newsService.toggleBookmark(item)
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isSaved ? self.tokens.onAccentInk : self.tokens.primaryInk.opacity(0.75))
                            .frame(width: 22, height: 22)
                            .background(
                                (isSaved ? self.tokens.accent : self.tokens.card.opacity(0.88)),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(5)
                }
                
                HStack(alignment: .top, spacing: 5) {
                    if !isRead {
                        Circle()
                            .fill(self.tokens.accent)
                            .frame(width: 5.5, height: 5.5)
                            .padding(.top, 5)
                    }
                    Text(item.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(self.tokens.primaryInk.opacity(isRead && !isSelected ? 0.72 : 0.94))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                HStack(spacing: 6) {
                    if !publisher.isEmpty {
                        Text(publisher)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(self.tokens.primaryInk.opacity(0.48))
                            .lineLimit(1)
                    } else {
                        Text(item.resolvedCategory.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(self.tokens.primaryInk.opacity(0.48))
                    }
                    Spacer(minLength: 2)
                    if let heat = item.heatScore, heat > 0 {
                        Text("\(heat)°")
                            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(self.tokens.accentText)
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? self.tokens.insetHover : self.tokens.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? self.tokens.accent.opacity(0.55) : self.tokens.hairline, lineWidth: isSelected ? 1.2 : 0.7)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    private func listRow(_ item: AIHotNewsItem) -> some View {
        let isSelected = (self.selectedItem?.id == item.id)
        let isRead = self.newsService.isRead(item)
        let isSaved = self.newsService.isBookmarked(item)
        let publisher = item.displayPublisherLabel
        
        return Button {
            self.selectedItemID = item.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(isRead ? Color.clear : self.tokens.accent)
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(self.tokens.primaryInk.opacity(isRead && !isSelected ? 0.72 : 0.94))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 8) {
                        Text(item.resolvedCategory.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(self.tokens.accentText)
                        if !publisher.isEmpty {
                            Text(publisher)
                                .font(.system(size: 10))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.48))
                                .lineLimit(1)
                        }
                        if let date = item.publishedAt {
                            Text(Self.relativeTimeString(from: date))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.42))
                        }
                        Spacer()
                        if let heat = item.heatScore, heat > 0 {
                            Text("\(heat)°")
                                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.tokens.accentText)
                        }
                    }
                }
                
                Button {
                    self.newsService.toggleBookmark(item)
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSaved ? self.tokens.accent : self.tokens.primaryInk.opacity(0.35))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? self.tokens.insetHover : self.tokens.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? self.tokens.accent.opacity(0.55) : self.tokens.hairline, lineWidth: isSelected ? 1.1 : 0.6)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    // MARK: Reader & Capture Pane
    
    @ViewBuilder
    private var readerPane: some View {
        if let item = self.selectedItem {
            let cover = self.newsService.coverImage(for: item)
            let isSaved = self.newsService.isBookmarked(item)
            let isGenerating = (self.newsService.isGeneratingBriefID == item.id)
            let aiBrief = self.newsService.aiBriefs[item.id]
            let publisher = item.displayPublisherLabel
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    if let cover {
                        Image(nsImage: cover)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(self.tokens.hairline, lineWidth: 0.7)
                            )
                    }
                    
                    // Metadata strip
                    HStack(spacing: 8) {
                        Text(item.resolvedCategory.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(self.tokens.accentText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(self.tokens.positivePillBg, in: Capsule())
                        
                        if !publisher.isEmpty {
                            Text(publisher)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.62))
                        }
                        
                        if let date = item.publishedAt {
                            Text(Self.relativeTimeString(from: date))
                                .font(.system(size: 11.5).monospacedDigit())
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.46))
                        }
                        
                        if let heat = item.heatScore, heat > 0 {
                            Text("\(heat)°")
                                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.tokens.accentText)
                        }
                        
                        Spacer()
                        
                        if let statusToast = self.statusToast {
                            Text(statusToast)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(self.tokens.accentText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(self.tokens.positivePillBg, in: Capsule())
                                .transition(.opacity)
                        }
                    }
                    
                    // Headline
                    Text(item.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                    
                    // Workflow Action Bar
                    HStack(spacing: 8) {
                        Button {
                            self.extractToNewDocument(item)
                        } label: {
                            Label(AppLanguage.text("摘录为新文档", en: "Extract to Doc"), systemImage: "doc.badge.plus")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(self.tokens.onAccentInk)
                                .padding(.horizontal, 11)
                                .frame(height: 30)
                                .background(self.tokens.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        
                        Button {
                            self.appendToWeeklyReportFragments(item)
                        } label: {
                            Label(AppLanguage.text("加入周报素材", en: "Add to Weekly"), systemImage: "text.badge.plus")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.86))
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(self.tokens.hairline, lineWidth: 0.7)
                                )
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        
                        Button {
                            self.newsService.toggleBookmark(item)
                        } label: {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(isSaved ? self.tokens.accent : self.tokens.primaryInk.opacity(0.72))
                                .frame(width: 30, height: 30)
                                .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(AppLanguage.text("收藏", en: "Bookmark"))
                        
                        Button {
                            self.copyMarkdownCitation(item)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.72))
                                .frame(width: 30, height: 30)
                                .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(AppLanguage.text("复制引用链接", en: "Copy Citation"))
                        
                        if let url = item.url {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Label(AppLanguage.text("原文", en: "Open"), systemImage: "arrow.up.right")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(self.tokens.primaryInk.opacity(0.78))
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                    
                    // Extracted Excerpt / Summary
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLanguage.text("摘要导读", en: "Summary"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(self.tokens.primaryInk.opacity(0.55))
                        
                        if let summary = item.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.88))
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        } else {
                            Text(AppLanguage.text("正在提取原文摘要，或点击下方「AI 速读提炼」生成结构化要点。", en: "Loading excerpt, or use AI Brief below."))
                                .font(.system(size: 12.5))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.46))
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(self.tokens.hairline, lineWidth: 0.7)
                    )
                    
                    // AI Brief Panel
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(AppLanguage.text("AI 速读提炼", en: "AI Brief"), systemImage: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(self.tokens.accentText)
                            Spacer()
                            Button {
                                Task {
                                    await self.newsService.generateAIBrief(for: item)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if isGenerating {
                                        ProgressView()
                                            .controlSize(.small)
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: aiBrief == nil ? "wand.and.stars" : "arrow.clockwise")
                                            .font(.system(size: 10.5, weight: .medium))
                                    }
                                    Text(
                                        isGenerating
                                            ? AppLanguage.text("提炼中", en: "Summarizing")
                                            : (aiBrief == nil
                                                ? AppLanguage.text("一键提炼", en: "Generate Brief")
                                                : AppLanguage.text("重新提炼", en: "Regenerate"))
                                    )
                                    .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(self.tokens.accentText)
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(self.tokens.positivePillBg, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(isGenerating)
                        }
                        
                        if let aiBrief, !aiBrief.isEmpty {
                            Text(aiBrief)
                                .font(.system(size: 12.5))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.90))
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        } else if let err = self.newsService.briefErrorMessage, !err.isEmpty {
                            HStack(spacing: 8) {
                                Text(err)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(self.tokens.primaryInk.opacity(0.64))
                                Spacer()
                                if !AIService.shared.isConfigured {
                                    Button(AppLanguage.text("打开 AI 设置", en: "AI Settings")) {
                                        (NSApp.delegate as? AppDelegate)?.showAIPreferences(nil)
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                    .buttonStyle(.plain)
                                    .foregroundStyle(self.tokens.accentText)
                                }
                            }
                        } else {
                            Text(AppLanguage.text("提炼核心变化、行业影响及可用于写作的思考角度。", en: "Synthesize key takeaways and writing angles."))
                                .font(.system(size: 12))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.46))
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(self.tokens.hairline, lineWidth: 0.7)
                    )
                    
                    // Quick Annotation / Note
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(AppLanguage.text("随手批注", en: "Quick Note"))
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.55))
                            Spacer()
                            if !self.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(AppLanguage.text("已自动保存", en: "Saved"))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(self.tokens.primaryInk.opacity(0.42))
                            }
                        }
                        
                        TextEditor(text: self.$noteDraft)
                            .font(.system(size: 12.5))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 72, maxHeight: 120)
                            .padding(8)
                            .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .onChange(of: self.noteDraft) { _, newValue in
                                self.newsService.setNote(newValue, for: item.id)
                            }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(self.tokens.hairline, lineWidth: 0.7)
                    )
                }
                .padding(18)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.28))
                Text(AppLanguage.text("选择左侧任意资讯查看详情", en: "Select a story to read"))
                    .font(.system(size: 13))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.52))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    
    // MARK: Actions
    
    private func syncSelectionSideEffects() {
        guard let item = self.selectedItem else { return }
        if self.selectedItemID != item.id {
            self.selectedItemID = item.id
        }
        self.newsService.markRead(item)
        self.noteDraft = self.newsService.note(for: item.id)
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
    
    
    private func extractToNewDocument(_ item: AIHotNewsItem) {
        var sections: [String] = ["# \(item.title)", ""]
        var meta: [String] = ["- 分类：\(item.resolvedCategory.label)"]
        let publisher = item.displayPublisherLabel
        if !publisher.isEmpty {
            meta.append("- 来源：\(publisher)")
        }
        meta.append("- 原文：\(item.urlString)")
        sections.append(meta.joined(separator: "\n"))
        
        if let summary = item.summary, !summary.isEmpty {
            sections.append("\n## 原文摘要\n\n\(summary)")
        }
        if let brief = self.newsService.aiBriefs[item.id], !brief.isEmpty {
            sections.append("\n## AI 速读要点\n\n\(brief)")
        }
        let note = self.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            sections.append("\n## 个人批注\n\n\(note)")
        }
        let markdown = sections.joined(separator: "\n") + "\n"
        
        if let onOpenExcerptDocument = self.onOpenExcerptDocument {
            onOpenExcerptDocument(item.title, markdown)
            return
        }
        
        if let controller = NSDocumentController.shared as? DocumentController {
            let activeWC = (NSApp.mainWindow?.windowController as? DocumentWindowController)
                ?? NSApp.orderedWindows.compactMap { $0.windowController as? DocumentWindowController }.first
            do {
                let doc = try controller.openUntitledDocument(content: markdown, title: item.title, display: activeWC == nil)
                doc.setSyntax(name: SyntaxName.markdown)
                if let activeWC, let docVC = activeWC.documentViewController {
                    activeWC.workspaceContentViewController?.hideInWindowCenter()
                    docVC.openOrFocusDocument(doc, splitRight: false)
                    activeWC.window?.makeKeyAndOrderFront(nil)
                }
                AnalyticsManager.shared.recordFileCreated()
            } catch {
                NSApp.presentError(error)
            }
        }
    }
    
    
    private func appendToWeeklyReportFragments(_ item: AIHotNewsItem) {
        let db = CotLocalDatabase.shared
        let existing = db.string(forKey: CotLocalDatabase.ConfigKey.weeklyReportFragments)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = ["- [\(item.title)](\(item.urlString))"]
        let note = self.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            lines.append("  - 批注：\(note)")
        } else if let brief = self.newsService.aiBriefs[item.id], !brief.isEmpty {
            let oneLine = brief.replacingOccurrences(of: "\n", with: " ")
            lines.append("  - 要点：\(String(oneLine.prefix(160)))")
        }
        let entry = lines.joined(separator: "\n")
        let next = existing.isEmpty ? entry : "\(existing)\n\(entry)"
        db.set(next, forKey: CotLocalDatabase.ConfigKey.weeklyReportFragments)
        self.showToast(AppLanguage.text("已加入周报素材", en: "Added to weekly fragments"))
    }
    
    
    private func copyMarkdownCitation(_ item: AIHotNewsItem) {
        let citation = "[\(item.title)](\(item.urlString))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(citation, forType: .string)
        self.showToast(AppLanguage.text("已复制引用", en: "Citation copied"))
    }
    
    
    private func showToast(_ text: String) {
        withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.16)) {
            self.statusToast = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.16)) {
                if self.statusToast == text {
                    self.statusToast = nil
                }
            }
        }
    }
    
    
    private static func relativeTimeString(from date: Date) -> String {
        let interval = max(0, Date().timeIntervalSince(date))
        if interval < 3600 {
            let mins = max(1, Int(interval / 60))
            return "\(mins)分钟前"
        }
        if interval < 86_400 {
            let hours = Int(interval / 3600)
            return "\(hours)小时前"
        }
        let days = Int(interval / 86_400)
        return "\(days)天前"
    }
}
