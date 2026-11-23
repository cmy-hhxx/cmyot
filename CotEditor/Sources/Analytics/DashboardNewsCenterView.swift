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

/// Interactive Readwise/Substack-inspired editorial NEWS workspace embedded inside the Analytics Dashboard.
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
                case .signal: AppLanguage.text("精选", en: "Top")
                case .latest: AppLanguage.text("最新", en: "Latest")
                case .heat: AppLanguage.text("热度", en: "Hot")
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
                            .frame(height: max(200, geo.size.height * 0.44))
                        Rectangle()
                            .fill(self.tokens.hairline)
                            .frame(height: 0.75)
                        self.readerPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    let feedW = max(320, min(440, geo.size.width * 0.42))
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
            self.newsService.preloadFeedResources(limit: 24)
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
                    Text(AppLanguage.text("返回看板", en: "Back"))
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
            
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.45))
                TextField(AppLanguage.text("搜索", en: "Search"), text: self.$searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(self.tokens.primaryInk)
                    .frame(minWidth: 110, maxWidth: 180)
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
            .help(AppLanguage.text("刷新", en: "Refresh"))
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
    
    
    // MARK: Feed Pane (Top-Right 77° Badges, Clean Compact Cards)
    
    private func feedPane(isCompact: Bool) -> some View {
        let items = self.displayedItems
        return Group {
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: self.activeFilter == .saved ? "bookmark" : "newspaper")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(self.tokens.primaryInk.opacity(0.30))
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
                ZStack(alignment: .topLeading) {
                    if let cover {
                        GeometryReader { geo in
                            Image(nsImage: cover)
                                .resizable()
                                .interpolation(.medium)
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        }
                        .frame(height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(self.tokens.inset)
                            .frame(height: 84)
                            .overlay(
                                Text(item.resolvedCategory.badgeLabel.isEmpty ? "AI" : item.resolvedCategory.badgeLabel)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(self.tokens.accentText)
                            )
                    }
                    
                    HStack(alignment: .top) {
                        if isSaved || isSelected {
                            Button {
                                self.newsService.toggleBookmark(item)
                            } label: {
                                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(isSaved ? self.tokens.onAccentInk : self.tokens.primaryInk.opacity(0.78))
                                    .frame(width: 21, height: 21)
                                    .background(
                                        (isSaved ? self.tokens.accent : self.tokens.card.opacity(0.90)),
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Spacer(minLength: 4)
                        
                        if let heat = item.heatScore, heat > 0 {
                            self.heatCapsule(heat)
                        }
                    }
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
                    Text(publisher.isEmpty ? item.resolvedCategory.label : publisher)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(self.tokens.primaryInk.opacity(0.46))
                        .lineLimit(1)
                    Spacer()
                    if let date = item.publishedAt {
                        Text(Self.relativeTimeString(from: date))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(self.tokens.primaryInk.opacity(0.38))
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
                    .padding(.top, 6)
                
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(self.tokens.primaryInk.opacity(isRead && !isSelected ? 0.72 : 0.94))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if let heat = item.heatScore, heat > 0 {
                            self.heatCapsule(heat)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text(item.resolvedCategory.label)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(self.tokens.accentText)
                        if !publisher.isEmpty {
                            Text(publisher)
                                .font(.system(size: 10.5))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.48))
                                .lineLimit(1)
                        }
                        if let date = item.publishedAt {
                            Text(Self.relativeTimeString(from: date))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.40))
                        }
                        Spacer()
                        Button {
                            self.newsService.toggleBookmark(item)
                        } label: {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isSaved ? self.tokens.accent : self.tokens.primaryInk.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
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
    
    
    private func heatCapsule(_ heat: Int) -> some View {
        Text("\(heat)°")
            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(self.tokens.accentText)
            .padding(.horizontal, 6.5)
            .padding(.vertical, 2)
            .background(self.tokens.card.opacity(0.92), in: Capsule())
            .overlay(Capsule().strokeBorder(self.tokens.hairline, lineWidth: 0.5))
    }
    
    
    // MARK: Editorial Reader Sheet (Zero Small Explanatory Text)
    
    @ViewBuilder
    private var readerPane: some View {
        if let item = self.selectedItem {
            let cover = self.newsService.coverImage(for: item)
            let isSaved = self.newsService.isBookmarked(item)
            let isGenerating = (self.newsService.isGeneratingBriefID == item.id)
            let aiBrief = self.newsService.aiBriefs[item.id]
            let publisher = item.displayPublisherLabel
            let summaryText = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isLoadingSummary = summaryText.isEmpty && !self.newsService.hasFinishedDetailFetch(for: item.id)
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    // Header Metadata Bar
                    HStack(alignment: .center, spacing: 8) {
                        Text(item.resolvedCategory.label)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(self.tokens.accentText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(self.tokens.positivePillBg, in: Capsule())
                        
                        if !publisher.isEmpty {
                            Text(publisher)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.68))
                        }
                        
                        if let date = item.publishedAt {
                            Text(Self.relativeTimeString(from: date))
                                .font(.system(size: 11.5).monospacedDigit())
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.44))
                        }
                        
                        Spacer(minLength: 8)
                        
                        if let statusToast = self.statusToast {
                            Text(statusToast)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(self.tokens.accentText)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(self.tokens.positivePillBg, in: Capsule())
                                .transition(.opacity)
                        }
                        
                        if let heat = item.heatScore, heat > 0 {
                            self.heatCapsule(heat)
                        }
                    }
                    
                    // Commanding Headline
                    Text(item.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Action Toolbar Strip
                    HStack(spacing: 8) {
                        Button {
                            self.extractToNewDocument(item)
                        } label: {
                            Label(AppLanguage.text("摘录成稿", en: "Extract"), systemImage: "doc.badge.plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(self.tokens.onAccentInk)
                                .padding(.horizontal, 12)
                                .frame(height: 31)
                                .background(self.tokens.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        
                        Button {
                            self.appendToWeeklyReportFragments(item)
                        } label: {
                            Label(AppLanguage.text("入周报", en: "Weekly"), systemImage: "text.badge.plus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.86))
                                .padding(.horizontal, 11)
                                .frame(height: 31)
                                .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        
                        Button {
                            Task {
                                await self.newsService.generateAIBrief(for: item)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isGenerating ? "hourglass" : "sparkles")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(aiBrief == nil ? AppLanguage.text("AI 提炼", en: "AI Brief") : AppLanguage.text("重新提炼", en: "Regenerate"))
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(self.tokens.accentText)
                            .padding(.horizontal, 11)
                            .frame(height: 31)
                            .background(self.tokens.positivePillBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isGenerating)
                        .pointerStyle(.link)
                        
                        Spacer(minLength: 4)
                        
                        Button {
                            self.newsService.toggleBookmark(item)
                        } label: {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(isSaved ? self.tokens.accent : self.tokens.primaryInk.opacity(0.72))
                                .frame(width: 31, height: 31)
                                .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(AppLanguage.text("收藏", en: "Bookmark"))
                        
                        Button {
                            self.copyMarkdownCitation(item)
                        } label: {
                            Image(systemName: "link")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.72))
                                .frame(width: 31, height: 31)
                                .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(AppLanguage.text("复制链接", en: "Copy Link"))
                        
                        if let url = item.url {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Label(AppLanguage.text("原文", en: "Open"), systemImage: "arrow.up.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(self.tokens.primaryInk.opacity(0.84))
                                    .padding(.horizontal, 10)
                                    .frame(height: 31)
                                    .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                    
                    // Hero Cover Banner
                    if let cover {
                        Image(nsImage: cover)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(self.tokens.hairline, lineWidth: 0.7)
                            )
                    }
                    
                    // Article Body Excerpt (with silent skeleton while preloading — zero explanatory text)
                    if !summaryText.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(self.tokens.accent.opacity(0.45))
                                .frame(width: 3)
                            
                            Text(summaryText)
                                .font(.system(size: 14.5, weight: .regular))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.90))
                                .lineSpacing(6)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .background(self.tokens.inset.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if isLoadingSummary {
                        NewsSkeletonShimmerBlock(tokens: self.tokens)
                    }
                    
                    // AI Brief Sheet (rendered ONLY when actively generating, generated, or displaying settings error)
                    if isGenerating || (aiBrief?.isEmpty == false) || (self.newsService.briefErrorMessage?.isEmpty == false) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(self.tokens.accentText)
                                Text(AppLanguage.text("AI 提炼", en: "AI Brief"))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(self.tokens.accentText)
                                Spacer()
                            }
                            
                            if isGenerating && (aiBrief?.isEmpty ?? true) {
                                NewsSkeletonShimmerBlock(tokens: self.tokens)
                            } else if let aiBrief, !aiBrief.isEmpty {
                                Text(aiBrief)
                                    .font(.system(size: 13.5, weight: .regular))
                                    .foregroundStyle(self.tokens.primaryInk.opacity(0.92))
                                    .lineSpacing(5)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else if let err = self.newsService.briefErrorMessage, !err.isEmpty {
                                HStack {
                                    Text(err)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(self.tokens.primaryInk.opacity(0.70))
                                    Spacer()
                                    if !AIService.shared.isConfigured {
                                        Button(AppLanguage.text("配置模型", en: "AI Settings")) {
                                            (NSApp.delegate as? AppDelegate)?.showAIPreferences(nil)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(self.tokens.positivePillBg.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(self.tokens.accent.opacity(0.24), lineWidth: 0.75)
                        )
                    }
                    
                    // Minimal Inline Note Field (no explanatory labels or saved-status captions)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "pencil.line")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(self.tokens.primaryInk.opacity(0.45))
                            .padding(.top, 3)
                        
                        TextField(AppLanguage.text("批注…", en: "Note…"), text: self.$noteDraft, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(self.tokens.primaryInk)
                            .lineLimit(2...6)
                            .onChange(of: self.noteDraft) { _, newValue in
                                self.newsService.setNote(newValue, for: item.id)
                            }
                    }
                    .padding(12)
                    .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(self.tokens.hairline, lineWidth: 0.7)
                    )
                }
                .padding(24)
                .frame(maxWidth: 700, alignment: .leading)
                .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
                )
                .shadow(color: self.tokens.cardShadow, radius: 10, y: 4)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.26))
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
            sections.append("\n## AI 提炼\n\n\(brief)")
        }
        let note = self.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            sections.append("\n## 批注\n\n\(note)")
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
        self.showToast(AppLanguage.text("已加入周报", en: "Added"))
    }
    
    
    private func copyMarkdownCitation(_ item: AIHotNewsItem) {
        let citation = "[\(item.title)](\(item.urlString))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(citation, forType: .string)
        self.showToast(AppLanguage.text("已复制", en: "Copied"))
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


private struct NewsSkeletonShimmerBlock: View {
    
    let tokens: StudioColorTokens
    @State private var pulse = false
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(self.tokens.primaryInk.opacity(self.pulse ? 0.11 : 0.05))
                .frame(maxWidth: .infinity)
                .frame(height: 11)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(self.tokens.primaryInk.opacity(self.pulse ? 0.11 : 0.05))
                .frame(maxWidth: .infinity)
                .frame(height: 11)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(self.tokens.primaryInk.opacity(self.pulse ? 0.11 : 0.05))
                .frame(width: 220, height: 11)
        }
        .padding(14)
        .background(self.tokens.inset.opacity(0.60), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                self.pulse = true
            }
        }
    }
}
