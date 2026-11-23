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

/// Flagship editorial NEWSroom & dual-mode Reader (Magazine Readability + Embedded WebKit) inside Analytics Dashboard.
struct DashboardNewsCenterView: View {
    
    enum FeedFilter: Hashable, Identifiable {
        case category(NewsFeedCategory)
        case unread
        case saved
        
        var id: String {
            switch self {
                case .category(let cat): "cat:\(cat.rawValue)"
                case .unread: "unread"
                case .saved: "saved"
            }
        }
        
        var label: String {
            switch self {
                case .category(let cat): cat == .xSocial ? "X" : cat.label
                case .unread: AppLanguage.text("未读", en: "Unread")
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
                case .cards: "rectangle.grid.1x2"
                case .list: "list.bullet"
            }
        }
        
        var label: String {
            switch self {
                case .cards: AppLanguage.text("画报", en: "Magazine")
                case .list: AppLanguage.text("列表", en: "List")
            }
        }
    }
    
    enum ReaderMode: String, CaseIterable, Identifiable {
        case editorial
        case web
        
        var id: String { self.rawValue }
        
        var label: String {
            switch self {
                case .editorial: AppLanguage.text("精读", en: "Reader")
                case .web: AppLanguage.text("网页", en: "Web")
            }
        }
        
        var icon: String {
            switch self {
                case .editorial: "doc.plaintext"
                case .web: "globe"
            }
        }
    }
    
    private static let bodyFontSizes: [CGFloat] = [14.0, 15.5, 17.0, 19.0]
    
    @Bindable var newsService: AIHotNewsService
    let tokens: StudioColorTokens
    let initialSelectedID: String?
    let onClose: () -> Void
    var onOpenExcerptDocument: ((String, String) -> Void)?
    
    @State private var activeFilter: FeedFilter = .category(.all)
    @State private var sortOrder: SortOrder = .signal
    @State private var layoutMode: FeedLayoutMode = .cards
    @State private var readerMode: ReaderMode = .editorial
    @State private var isSidebarCollapsed: Bool = false
    @State private var searchText: String = ""
    @State private var selectedItemID: String?
    @State private var noteDraft: String = ""
    @State private var statusToast: String?
    @State private var fontScaleIndex: Int = {
        let raw = Int(CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.newsReaderFontScale, default: "1")) ?? 1
        return min(max(0, raw), 3)
    }()
    @State private var webProgress: Double = 0
    @State private var webIsLoading: Bool = false
    
    
    private var bodyFontSize: CGFloat {
        Self.bodyFontSizes[min(max(0, self.fontScaleIndex), Self.bodyFontSizes.count - 1)]
    }
    
    private var displayedItems: [AIHotNewsItem] {
        let base: [AIHotNewsItem] = switch self.activeFilter {
            case .category(let category):
                category == .all
                    ? self.newsService.items
                    : self.newsService.items.filter { $0.resolvedCategory == category }
            case .unread:
                self.newsService.items.filter { !self.newsService.isRead($0) }
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
            self.topCommandBar
            
            Rectangle()
                .fill(self.tokens.hairline)
                .frame(height: 0.75)
            
            GeometryReader { geo in
                let compactWidth = geo.size.width < 780
                if compactWidth {
                    VStack(spacing: 0) {
                        if !self.isSidebarCollapsed {
                            self.feedStreamPane(isCompact: true)
                                .frame(height: max(190, geo.size.height * 0.40))
                            Rectangle()
                                .fill(self.tokens.hairline)
                                .frame(height: 0.75)
                        }
                        self.readerWorkspacePane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    let feedW = min(400, max(336, floor(geo.size.width * 0.34)))
                    HStack(spacing: 0) {
                        if !self.isSidebarCollapsed {
                            self.feedStreamPane(isCompact: false)
                                .frame(width: feedW)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            
                            Rectangle()
                                .fill(self.tokens.hairline)
                                .frame(width: 0.75)
                        }
                        
                        self.readerWorkspacePane
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
            self.newsService.preloadFeedResources(limit: 20)
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
    
    
    // MARK: - Top Architectural Command Bar
    
    private var topCommandBar: some View {
        HStack(spacing: 8) {
            Button(action: self.onClose) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(AppLanguage.text("返回看板", en: "Back"))
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(self.tokens.primaryInk.opacity(0.86))
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
            
            Button {
                withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.20)) {
                    self.isSidebarCollapsed.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(self.isSidebarCollapsed ? self.tokens.accentText : self.tokens.primaryInk.opacity(0.72))
                    .frame(width: 30, height: 30)
                    .background(
                        self.isSidebarCollapsed ? self.tokens.positivePillBg : self.tokens.card,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
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
                    self.filterPill(.unread)
                    self.filterPill(.saved, count: self.newsService.bookmarkedIDs.count)
                }
            }
            .frame(maxWidth: 420)
            
            Spacer(minLength: 8)
            
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.45))
                TextField(AppLanguage.text("搜索", en: "Search"), text: self.$searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(self.tokens.primaryInk)
                    .frame(minWidth: 100, maxWidth: 170)
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
            
            HStack(spacing: 2) {
                ForEach(SortOrder.allCases) { order in
                    let active = (self.sortOrder == order)
                    Button {
                        withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.16)) {
                            self.sortOrder = order
                        }
                    } label: {
                        Text(order.label)
                            .font(.system(size: 11, weight: active ? .semibold : .medium))
                            .foregroundStyle(active ? self.tokens.onAccentInk : self.tokens.primaryInk.opacity(0.66))
                            .padding(.horizontal, 7)
                            .frame(height: 24)
                            .background(active ? self.tokens.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(3)
            .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
            )
            
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
            .pointerStyle(.link)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
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
    
    
    // MARK: - Left Editorial Stream (Hero Lead Banner + Horizontal Retina Story Cards)
    
    private func feedStreamPane(isCompact: Bool) -> some View {
        let items = self.displayedItems
        return Group {
            if items.isEmpty {
                VStack {
                    Image(systemName: self.activeFilter == .saved ? "bookmark" : "newspaper")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(self.tokens.primaryInk.opacity(0.26))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: self.layoutMode == .cards ? 9 : 6) {
                            if self.layoutMode == .cards && !isCompact {
                                if let hero = items.first, self.searchText.isEmpty {
                                    self.featuredLeadCard(hero)
                                        .id(hero.id)
                                    ForEach(items.dropFirst()) { item in
                                        self.magazineStoryRow(item)
                                            .id(item.id)
                                    }
                                } else {
                                    ForEach(items) { item in
                                        self.magazineStoryRow(item)
                                            .id(item.id)
                                    }
                                }
                            } else {
                                ForEach(items) { item in
                                    self.compactListRow(item)
                                        .id(item.id)
                                }
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: self.selectedItemID) { _, nextID in
                        guard let nextID else { return }
                        withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.20)) {
                            scrollProxy.scrollTo(nextID, anchor: .center)
                        }
                    }
                }
            }
        }
    }
    
    
    private func featuredLeadCard(_ item: AIHotNewsItem) -> some View {
        let isSelected = (self.selectedItem?.id == item.id)
        let isRead = self.newsService.isRead(item)
        let isSaved = self.newsService.isBookmarked(item)
        let cover = self.newsService.coverImage(for: item)
        let publisher = item.displayPublisherLabel
        
        return Button {
            self.selectedItemID = item.id
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .topLeading) {
                    if let cover {
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
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        self.fallbackCoverTile(for: item, cornerRadius: 10)
                            .frame(height: 124)
                    }
                    
                    HStack(alignment: .top) {
                        Button {
                            self.newsService.toggleBookmark(item)
                        } label: {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isSaved ? self.tokens.onAccentInk : self.tokens.primaryInk.opacity(0.80))
                                .frame(width: 24, height: 24)
                                .background(isSaved ? self.tokens.accent : self.tokens.card.opacity(0.90), in: Circle())
                        }
                        .buttonStyle(.plain)
                        
                        Spacer(minLength: 4)
                        
                        if let heat = item.heatScore, heat > 0 {
                            self.heatCapsule(heat)
                        }
                    }
                    .padding(7)
                }
                
                HStack(alignment: .top, spacing: 6) {
                    if !isRead {
                        Circle()
                            .fill(self.tokens.accent)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                    }
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(self.tokens.primaryInk.opacity(isRead && !isSelected ? 0.78 : 0.96))
                        .lineLimit(2)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                HStack(spacing: 6) {
                    Text(item.resolvedCategory.badgeLabel.isEmpty ? "AI" : item.resolvedCategory.badgeLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(self.tokens.accentText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(self.tokens.positivePillBg, in: Capsule())
                    
                    if !publisher.isEmpty {
                        Text(publisher)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(self.tokens.primaryInk.opacity(0.50))
                            .lineLimit(1)
                    }
                    Spacer()
                    if let date = item.publishedAt {
                        Text(Self.relativeTimeString(from: date))
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(self.tokens.primaryInk.opacity(0.40))
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? self.tokens.insetHover : self.tokens.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isSelected ? self.tokens.accent.opacity(0.60) : self.tokens.hairline, lineWidth: isSelected ? 1.3 : 0.75)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    private func magazineStoryRow(_ item: AIHotNewsItem) -> some View {
        let isSelected = (self.selectedItem?.id == item.id)
        let isRead = self.newsService.isRead(item)
        let isSaved = self.newsService.isBookmarked(item)
        let cover = self.newsService.coverImage(for: item)
        let publisher = item.displayPublisherLabel
        
        return Button {
            self.selectedItemID = item.id
        } label: {
            HStack(alignment: .center, spacing: 11) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 5.5) {
                        if !isRead {
                            Circle()
                                .fill(self.tokens.accent)
                                .frame(width: 5.5, height: 5.5)
                                .padding(.top, 5.5)
                        }
                        Text(item.title)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(self.tokens.primaryInk.opacity(isRead && !isSelected ? 0.70 : 0.94))
                            .lineLimit(2)
                            .lineSpacing(1.5)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    HStack(spacing: 6) {
                        Text(publisher.isEmpty ? item.resolvedCategory.label : publisher)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(self.tokens.primaryInk.opacity(0.48))
                            .lineLimit(1)
                        
                        if let date = item.publishedAt {
                            Text(Self.relativeTimeString(from: date))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.38))
                        }
                        
                        Spacer(minLength: 2)
                        
                        if isSaved {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(self.tokens.accent)
                        }
                    }
                }
                
                ZStack(alignment: .topTrailing) {
                    if let cover {
                        GeometryReader { geo in
                            Image(nsImage: cover)
                                .resizable()
                                .interpolation(.high)
                                .antialiased(true)
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        }
                    } else {
                        self.fallbackCoverTile(for: item, cornerRadius: 8)
                    }
                    
                    if let heat = item.heatScore, heat > 0 {
                        Text("\(heat)°")
                            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(self.tokens.accentText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(self.tokens.card.opacity(0.92), in: Capsule())
                            .padding(3.5)
                    }
                }
                .frame(width: 88, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.55)
                )
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? self.tokens.insetHover : self.tokens.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? self.tokens.accent.opacity(0.58) : self.tokens.hairline, lineWidth: isSelected ? 1.2 : 0.7)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    private func compactListRow(_ item: AIHotNewsItem) -> some View {
        let isSelected = (self.selectedItem?.id == item.id)
        let isRead = self.newsService.isRead(item)
        let isSaved = self.newsService.isBookmarked(item)
        let publisher = item.displayPublisherLabel
        
        return Button {
            self.selectedItemID = item.id
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Circle()
                    .fill(isRead ? Color.clear : self.tokens.accent)
                    .frame(width: 5.5, height: 5.5)
                    .padding(.top, 6)
                
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(self.tokens.primaryInk.opacity(isRead && !isSelected ? 0.70 : 0.94))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if let heat = item.heatScore, heat > 0 {
                            self.heatCapsule(heat)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text(item.resolvedCategory.badgeLabel.isEmpty ? "AI" : item.resolvedCategory.badgeLabel)
                            .font(.system(size: 10, weight: .semibold))
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
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.38))
                        }
                        Spacer()
                        Button {
                            self.newsService.toggleBookmark(item)
                        } label: {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isSaved ? self.tokens.accent : self.tokens.primaryInk.opacity(0.34))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8.5)
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
    
    
    private func fallbackCoverTile(for item: AIHotNewsItem, cornerRadius: CGFloat) -> some View {
        let badge = item.resolvedCategory.badgeLabel.isEmpty ? "AI" : item.resolvedCategory.badgeLabel
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [self.tokens.accent.opacity(0.18), self.tokens.secondaryAccent.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(badge)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(self.tokens.accentText.opacity(0.84))
            )
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
    
    
    // MARK: - Right Dual-Mode Reader Workspace (Editorial Magazine + Embedded WebKit)
    
    @ViewBuilder
    private var readerWorkspacePane: some View {
        if let item = self.selectedItem {
            VStack(spacing: 0) {
                self.readerSubToolbar(for: item)
                
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(self.tokens.hairline)
                        .frame(height: 0.75)
                    
                    if self.readerMode == .web && self.webIsLoading {
                        GeometryReader { barGeo in
                            Rectangle()
                                .fill(self.tokens.accent)
                                .frame(width: max(16, barGeo.size.width * CGFloat(self.webProgress)), height: 2)
                                .animation(.linear(duration: 0.15), value: self.webProgress)
                        }
                        .frame(height: 2)
                    }
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
                    self.editorialMagazineScroll(for: item)
                }
            }
        } else {
            VStack {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.24))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    
    private func readerSubToolbar(for item: AIHotNewsItem) -> some View {
        let isSaved = self.newsService.isBookmarked(item)
        let isGenerating = (self.newsService.isGeneratingBriefID == item.id)
        let hasBrief = (self.newsService.aiBriefs[item.id]?.isEmpty == false)
        
        return HStack(spacing: 8) {
            // Segmented Reader / Web switcher
            HStack(spacing: 2) {
                ForEach(ReaderMode.allCases) { mode in
                    let active = (self.readerMode == mode)
                    Button {
                        withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.16)) {
                            self.readerMode = mode
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(mode.label)
                                .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                        }
                        .foregroundStyle(active ? self.tokens.onAccentInk : self.tokens.primaryInk.opacity(0.68))
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(active ? self.tokens.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(2.5)
            .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
            )
            
            if self.readerMode == .editorial {
                HStack(spacing: 0) {
                    Button {
                        self.adjustFontScale(by: -1)
                    } label: {
                        Text("A-")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(self.fontScaleIndex > 0 ? self.tokens.primaryInk.opacity(0.78) : self.tokens.primaryInk.opacity(0.28))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(self.fontScaleIndex <= 0)
                    
                    Rectangle()
                        .fill(self.tokens.hairline)
                        .frame(width: 0.75, height: 14)
                    
                    Button {
                        self.adjustFontScale(by: 1)
                    } label: {
                        Text("A+")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(self.fontScaleIndex < 3 ? self.tokens.primaryInk.opacity(0.78) : self.tokens.primaryInk.opacity(0.28))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(self.fontScaleIndex >= 3)
                }
                .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
                )
            }
            
            if let statusToast = self.statusToast {
                Text(statusToast)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(self.tokens.accentText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(self.tokens.positivePillBg, in: Capsule())
                    .transition(.opacity)
            }
            
            Spacer(minLength: 6)
            
            Button {
                Task {
                    await self.newsService.generateAIBrief(for: item)
                }
            } label: {
                HStack(spacing: 4.5) {
                    Image(systemName: isGenerating ? "hourglass" : "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    Text(hasBrief ? AppLanguage.text("重提炼", en: "Brief") : AppLanguage.text("AI 精读", en: "AI Brief"))
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(self.tokens.accentText)
                .padding(.horizontal, 10)
                .frame(height: 29)
                .background(self.tokens.positivePillBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
            .pointerStyle(.link)
            
            Button {
                self.extractToNewDocument(item)
            } label: {
                Label(AppLanguage.text("摘录成稿", en: "Extract"), systemImage: "doc.badge.plus")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(self.tokens.onAccentInk)
                    .padding(.horizontal, 11)
                    .frame(height: 29)
                    .background(self.tokens.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            Button {
                self.appendToWeeklyReportFragments(item)
            } label: {
                Label(AppLanguage.text("入周报", en: "Weekly"), systemImage: "text.badge.plus")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.86))
                    .padding(.horizontal, 10)
                    .frame(height: 29)
                    .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
                    )
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            Button {
                self.newsService.toggleBookmark(item)
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSaved ? self.tokens.accent : self.tokens.primaryInk.opacity(0.74))
                    .frame(width: 29, height: 29)
                    .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
                    )
            }
            .buttonStyle(.plain)
            
            Button {
                self.copyMarkdownCitation(item)
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.74))
                    .frame(width: 29, height: 29)
                    .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
                    )
            }
            .buttonStyle(.plain)
            
            if let url = item.url {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(self.tokens.primaryInk.opacity(0.78))
                        .frame(width: 29, height: 29)
                        .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
                        )
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(self.tokens.canvasTop.opacity(0.65))
    }
    
    
    private func editorialMagazineScroll(for item: AIHotNewsItem) -> some View {
        let cover = self.newsService.coverImage(for: item)
        let isGenerating = (self.newsService.isGeneratingBriefID == item.id)
        let aiBrief = self.newsService.aiBriefs[item.id]
        let publisher = item.displayPublisherLabel
        let blocks = self.newsService.resolvedArticleBlocks(for: item)
        let summaryText = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isLoadingArticle = self.newsService.loadingArticleIDs.contains(item.id)
            || (blocks.isEmpty && summaryText.isEmpty && !self.newsService.hasFinishedDetailFetch(for: item.id))
        let neighbors = self.adjacentItems
        
        return ScrollViewReader { readerProxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    // 1. Editorial Metadata Header
                    HStack(alignment: .center, spacing: 8) {
                        Text(item.resolvedCategory.label)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(self.tokens.accentText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(self.tokens.positivePillBg, in: Capsule())
                        
                        if !publisher.isEmpty {
                            Text(publisher)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.68))
                        }
                        
                        if let date = item.publishedAt {
                            Text(Self.relativeTimeString(from: date))
                                .font(.system(size: 11.5).monospacedDigit())
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.44))
                        }
                        
                        Spacer(minLength: 8)
                        
                        if let heat = item.heatScore, heat > 0 {
                            self.heatCapsule(heat)
                        }
                    }
                    .id("article-top")
                    
                    // 2. Commanding Magazine Headline
                    Text(item.title)
                        .font(.system(size: self.bodyFontSize + 6.5, weight: .bold))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // 3. AI Executive Brief Card (front-and-center when active)
                    if isGenerating || (aiBrief?.isEmpty == false) || (self.newsService.briefErrorMessage?.isEmpty == false) {
                        self.aiSynthesisCard(aiBrief: aiBrief, isGenerating: isGenerating)
                    }
                    
                    // 4. High-DPI Retina Hero Cover
                    if let cover {
                        Image(nsImage: cover)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 310)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
                            )
                    }
                    
                    // 5. Full Multi-Block Article Body (or Lead Excerpt / Silent Shimmer)
                    if !blocks.isEmpty {
                        VStack(alignment: .leading, spacing: 15) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                                self.articleBlockView(block)
                            }
                        }
                        .padding(.top, 2)
                    } else if !summaryText.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 12) {
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(self.tokens.accent.opacity(0.55))
                                    .frame(width: 3)
                                
                                Text(summaryText)
                                    .font(.system(size: self.bodyFontSize, weight: .regular))
                                    .foregroundStyle(self.tokens.primaryInk.opacity(0.90))
                                    .lineSpacing(self.bodyFontSize * 0.45)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(16)
                            .background(self.tokens.inset.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            
                            if isLoadingArticle {
                                NewsSkeletonShimmerBlock(tokens: self.tokens)
                            }
                        }
                    } else if isLoadingArticle {
                        NewsSkeletonShimmerBlock(tokens: self.tokens)
                    }
                    
                    Rectangle()
                        .fill(self.tokens.hairline)
                        .frame(height: 0.75)
                        .padding(.top, 4)
                    
                    // 6. Minimal Inline Annotation Field
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "pencil.line")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(self.tokens.primaryInk.opacity(0.45))
                            .padding(.top, 3)
                        
                        TextField(AppLanguage.text("批注…", en: "Note…"), text: self.$noteDraft, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13.5))
                            .foregroundStyle(self.tokens.primaryInk)
                            .lineLimit(2...6)
                            .onChange(of: self.noteDraft) { _, newValue in
                                self.newsService.setNote(newValue, for: item.id)
                            }
                    }
                    .padding(13)
                    .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(self.tokens.hairline, lineWidth: 0.7)
                    )
                    
                    // 7. Continuous Reading Adjacent Story Navigation
                    if neighbors.previous != nil || neighbors.next != nil {
                        HStack(spacing: 12) {
                            if let prev = neighbors.previous {
                                self.neighborCard(prev, isNext: false) {
                                    self.selectedItemID = prev.id
                                    readerProxy.scrollTo("article-top", anchor: .top)
                                }
                            } else {
                                Spacer(minLength: 0)
                                    .frame(maxWidth: .infinity)
                            }
                            
                            if let next = neighbors.next {
                                self.neighborCard(next, isNext: true) {
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
                .padding(28)
                .frame(maxWidth: 740, alignment: .leading)
                .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.75)
                )
                .shadow(color: self.tokens.cardShadow, radius: 10, y: 4)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
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
                    .font(.system(size: self.bodyFontSize + (level <= 2 ? 3.0 : 1.5), weight: .semibold))
                    .foregroundStyle(self.tokens.primaryInk)
                    .padding(.top, 6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
            case .paragraph(let text):
                Text(text)
                    .font(.system(size: self.bodyFontSize, weight: .regular))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.90))
                    .lineSpacing(self.bodyFontSize * 0.46)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
            case .quote(let text):
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(self.tokens.accent)
                        .frame(width: 3)
                    
                    Text(text)
                        .font(.system(size: max(13.5, self.bodyFontSize - 0.5), weight: .regular))
                        .foregroundStyle(self.tokens.primaryInk.opacity(0.84))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(self.tokens.inset.opacity(0.70), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                
            case .code(let code):
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(code)
                        .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(self.tokens.primaryInk.opacity(0.92))
                        .textSelection(.enabled)
                        .padding(13)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(self.tokens.hairline, lineWidth: 0.65)
                )
                
            case .list(let items):
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 9) {
                            Circle()
                                .fill(self.tokens.accent.opacity(0.75))
                                .frame(width: 5, height: 5)
                                .padding(.top, self.bodyFontSize * 0.48)
                            
                            Text(line)
                                .font(.system(size: self.bodyFontSize, weight: .regular))
                                .foregroundStyle(self.tokens.primaryInk.opacity(0.90))
                                .lineSpacing(self.bodyFontSize * 0.40)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.leading, 4)
        }
    }
    
    
    private func aiSynthesisCard(aiBrief: String?, isGenerating: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(self.tokens.accentText)
                Text(AppLanguage.text("AI 精读", en: "AI Brief"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(self.tokens.accentText)
                Spacer()
            }
            
            if isGenerating && (aiBrief?.isEmpty ?? true) {
                NewsSkeletonShimmerBlock(tokens: self.tokens)
            } else if let aiBrief, !aiBrief.isEmpty {
                Text(aiBrief)
                    .font(.system(size: max(13.5, self.bodyFontSize - 1.0), weight: .regular))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.92))
                    .lineSpacing(5.5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !AIService.shared.isConfigured {
                Button(AppLanguage.text("配置模型", en: "AI Settings")) {
                    (NSApp.delegate as? AppDelegate)?.showAIPreferences(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if let err = self.newsService.briefErrorMessage, !err.isEmpty {
                Text(err)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.70))
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.tokens.positivePillBg.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(self.tokens.accent.opacity(0.26), lineWidth: 0.8)
        )
    }
    
    
    private func neighborCard(_ item: AIHotNewsItem, isNext: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if !isNext {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(self.tokens.accentText)
                }
                
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.86))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: isNext ? .trailing : .leading)
                
                if isNext {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(self.tokens.accentText)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(self.tokens.inset.opacity(0.75), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(self.tokens.hairline, lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    // MARK: - Actions & Helpers
    
    private func adjustFontScale(by delta: Int) {
        let next = min(max(0, self.fontScaleIndex + delta), Self.bodyFontSizes.count - 1)
        guard next != self.fontScaleIndex else { return }
        withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.14)) {
            self.fontScaleIndex = next
        }
        CotLocalDatabase.shared.set("\(next)", forKey: CotLocalDatabase.ConfigKey.newsReaderFontScale)
    }
    
    
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
        
        if let brief = self.newsService.aiBriefs[item.id], !brief.isEmpty {
            sections.append("\n## AI 精读\n\n\(brief)")
        }
        let note = self.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            sections.append("\n## 批注\n\n\(note)")
        }
        
        let blocks = self.newsService.resolvedArticleBlocks(for: item)
        if !blocks.isEmpty {
            sections.append("\n## 正文\n\n\(blocks.map(\.markdownText).joined(separator: "\n\n"))")
        } else if let summary = item.summary, !summary.isEmpty {
            sections.append("\n## 摘要\n\n\(summary)")
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


// MARK: - Silent Shimmer Skeleton

private struct NewsSkeletonShimmerBlock: View {
    
    let tokens: StudioColorTokens
    @State private var pulse = false
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
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
                .frame(width: 240, height: 11)
        }
        .padding(15)
        .background(self.tokens.inset.opacity(0.60), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                self.pulse = true
            }
        }
    }
}
