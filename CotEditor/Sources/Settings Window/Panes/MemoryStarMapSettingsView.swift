//
//  MemoryStarMapSettingsView.swift
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

import SwiftUI

enum MemoryStarMapScope: String, CaseIterable, Identifiable {
    
    case all
    case kyc
    case assets
    
    var id: String { self.rawValue }
    
    var label: String {
        switch self {
            case .all: AppLanguage.text("全部", en: "All")
            case .kyc: AppLanguage.text("KYC 画像", en: "KYC")
            case .assets: AppLanguage.text("关注资产", en: "Assets")
        }
    }
}


struct MemoryStarMapLeafDetail: Identifiable, Equatable {
    
    let id: String
    let clusterID: String
    let clusterTitle: String
    let title: String
    let subtitle: String
    let accentHex: String
    let primaryMetric: String?
    let badgeText: String?
    let bodyText: String
    let attributes: [(label: String, value: String)]
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.clusterID == rhs.clusterID
            && lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.primaryMetric == rhs.primaryMetric
            && lhs.bodyText == rhs.bodyText
    }
}


/// Strictly read-only Constellation Star-Map displaying the user's structured KYC profile
/// and portable SQLite asset collections inside Settings -> Memory.
struct MemoryStarMapSettingsView: View {
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var memoryStore = CotMemoryStore.shared
    @State private var scope: MemoryStarMapScope = .all
    @State private var searchText: String = ""
    @State private var focusedClusterID: String?
    @State private var collapsedClusterIDs: Set<String> = []
    @State private var selectedLeafID: String?
    @State private var quickLookLeafID: String?
    @Namespace private var scopePillNamespace
    
    
    var body: some View {
        let isDark = (self.colorScheme == .dark)
        let tokens = DashPalette.editorialTokens(isDark: isDark)
        let built = Self.buildConstellationClusters(
            memories: self.memoryStore.memories,
            stocks: self.memoryStore.stocks,
            podcasts: self.memoryStore.podcasts,
            feeds: self.memoryStore.feeds,
            creators: self.memoryStore.creators,
            scope: self.scope,
            collapsedClusterIDs: self.collapsedClusterIDs,
            searchQuery: self.searchText
        )
        let orderedLeafIDs = built.clusters.flatMap { $0.leaves.map(\.id) }
        let selectedDetail = self.selectedLeafID.flatMap { built.detailsByLeafID[$0] }
        let quickLookDetail = self.quickLookLeafID.flatMap { built.detailsByLeafID[$0] }
        let totalNodeCount = built.clusters.reduce(0) { $0 + $1.leaves.count }
        
        ZStack {
            VStack(spacing: 0) {
                self.topToolbar(tokens: tokens, totalNodeCount: totalNodeCount, clusterCount: built.clusters.count)
                
                Rectangle()
                    .fill(tokens.hairline)
                    .frame(height: 1)
                
                ZStack(alignment: .bottom) {
                    ConstellationStarMapView(
                        hubTitle: AppLanguage.text("记忆星图", en: "Memory Map"),
                        hubSubtitle: "\(totalNodeCount)",
                        clusters: built.clusters,
                        selectedLeafID: self.selectedLeafID,
                        focusedClusterID: self.focusedClusterID,
                        searchQuery: self.searchText,
                        onSelectLeaf: { leafID in
                            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                                self.selectedLeafID = (self.selectedLeafID == leafID) ? nil : leafID
                            }
                        },
                        onDoubleClickLeaf: { leafID in
                            self.selectedLeafID = leafID
                            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                                self.quickLookLeafID = leafID
                            }
                        },
                        onToggleCluster: { clusterID in
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                                if self.focusedClusterID == clusterID {
                                    self.focusedClusterID = nil
                                } else {
                                    self.focusedClusterID = clusterID
                                    self.collapsedClusterIDs.remove(clusterID)
                                }
                            }
                        },
                        clusterContextMenu: { _ in EmptyView() },
                        leafContextMenu: { leaf in
                            Button {
                                self.selectedLeafID = leaf.id
                                self.quickLookLeafID = leaf.id
                            } label: {
                                Label(AppLanguage.text("查看详情", en: "Inspect"), systemImage: "eye")
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    if let selectedDetail {
                        self.selectedSummaryPill(detail: selectedDetail, tokens: tokens)
                            .padding(.bottom, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            
            if let quickLookDetail,
               let currentIndex = orderedLeafIDs.firstIndex(of: quickLookDetail.id)
            {
                let canPrev = currentIndex > 0
                let canNext = currentIndex + 1 < orderedLeafIDs.count
                StarMapQuickLookOverlay(
                    title: quickLookDetail.title,
                    subtitle: quickLookDetail.subtitle,
                    canStepPrevious: canPrev,
                    canStepNext: canNext,
                    onPrevious: {
                        guard canPrev else { return }
                        let prevID = orderedLeafIDs[currentIndex - 1]
                        self.selectedLeafID = prevID
                        self.quickLookLeafID = prevID
                    },
                    onNext: {
                        guard canNext else { return }
                        let nextID = orderedLeafIDs[currentIndex + 1]
                        self.selectedLeafID = nextID
                        self.quickLookLeafID = nextID
                    },
                    onClose: {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                            self.quickLookLeafID = nil
                        }
                    },
                    headerActions: {
                        EmptyView()
                    },
                    bodyContent: {
                        self.readOnlyDetailSheetBody(detail: quickLookDetail, tokens: tokens)
                    }
                )
            }
        }
        .background(tokens.canvasTop)
        .onAppear {
            self.memoryStore.reloadFromDatabase()
        }
    }
    
    
    // MARK: - Top Control Strip (Zero Helper Copy)
    
    private func topToolbar(
        tokens: StudioColorTokens,
        totalNodeCount: Int,
        clusterCount: Int
    ) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                ForEach(MemoryStarMapScope.allCases) { item in
                    let isSelected = (self.scope == item)
                    Button {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                            self.scope = item
                            self.focusedClusterID = nil
                        }
                    } label: {
                        Text(item.label)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? tokens.primaryInk : tokens.primaryInk.opacity(0.62))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(tokens.card)
                                        .matchedGeometryEffect(id: "memoryScopePill", in: self.scopePillNamespace)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(3)
            .background(tokens.inset, in: Capsule())
            
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(AppLanguage.text("只读", en: "Read-Only"))
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(tokens.primaryInk.opacity(0.60))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(tokens.inset, in: Capsule())
            
            Spacer(minLength: 8)
            
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tokens.primaryInk.opacity(0.45))
                
                TextField(AppLanguage.text("检索节点", en: "Filter"), text: self.$searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .frame(width: 118)
                
                if !self.searchText.isEmpty {
                    Button {
                        self.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(tokens.primaryInk.opacity(0.42))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(tokens.inset, in: Capsule())
            .overlay(Capsule().strokeBorder(tokens.hairline, lineWidth: 0.75))
            
            Text("\(clusterCount) · \(totalNodeCount)")
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(tokens.primaryInk.opacity(0.55))
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }
    
    
    // MARK: - Bottom Selection Capsule & Read-Only Inspector
    
    private func selectedSummaryPill(detail: MemoryStarMapLeafDetail, tokens: StudioColorTokens) -> some View {
        let accent = Color(hexString: detail.accentHex)
        return HStack(spacing: 10) {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(detail.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(tokens.primaryInk)
                    .lineLimit(1)
                if !detail.subtitle.isEmpty {
                    Text(detail.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(tokens.primaryInk.opacity(0.56))
                        .lineLimit(1)
                }
            }
            
            if let badge = detail.badgeText, !badge.isEmpty {
                Text(badge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(accent.opacity(0.12), in: Capsule())
            }
            
            Button {
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                    self.quickLookLeafID = detail.id
                }
            } label: {
                HStack(spacing: 3) {
                    Text(AppLanguage.text("详情", en: "Inspect"))
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .foregroundStyle(tokens.primaryInk)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(tokens.inset, in: Capsule())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(tokens.hairlineStrong, lineWidth: 0.85))
        .shadow(color: Color.black.opacity(0.14), radius: 14, y: 6)
        .padding(.horizontal, 24)
    }
    
    
    private func readOnlyDetailSheetBody(detail: MemoryStarMapLeafDetail, tokens: StudioColorTokens) -> some View {
        let accent = Color(hexString: detail.accentHex)
        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text(detail.clusterTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(accent.opacity(0.12), in: Capsule())
                    
                    if let metric = detail.primaryMetric, !metric.isEmpty {
                        Text(metric)
                            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(tokens.primaryInk.opacity(0.76))
                            .padding(.horizontal, 9)
                            .frame(height: 22)
                            .background(tokens.inset, in: Capsule())
                    }
                    
                    Spacer(minLength: 0)
                    
                    Label(AppLanguage.text("只读档案", en: "Read-Only"), systemImage: "lock.fill")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(tokens.primaryInk.opacity(0.50))
                }
                
                if !detail.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(detail.bodyText)
                        .font(.system(size: 13.5))
                        .foregroundStyle(tokens.primaryInk.opacity(0.92))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(tokens.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                
                if !detail.attributes.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(detail.attributes.enumerated()), id: \.offset) { idx, pair in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(pair.label)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(tokens.primaryInk.opacity(0.52))
                                    .frame(width: 86, alignment: .leading)
                                
                                Text(pair.value)
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(tokens.primaryInk)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            
                            if idx + 1 < detail.attributes.count {
                                Rectangle()
                                    .fill(tokens.hairline)
                                    .frame(height: 0.75)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    
    // MARK: - Pure Deterministic Constellation Builder (Testable)
    
    static func buildConstellationClusters(
        memories: [UserKYCMemoryRecord],
        stocks: [WatchlistStockRecord],
        podcasts: [StoredPodcastRecord],
        feeds: [FollowedFeedRecord],
        creators: [FollowedCreatorRecord],
        scope: MemoryStarMapScope = .all,
        collapsedClusterIDs: Set<String> = [],
        searchQuery: String = ""
    ) -> (clusters: [StarMapClusterNode], detailsByLeafID: [String: MemoryStarMapLeafDetail]) {
        let needle = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        var clusters: [StarMapClusterNode] = []
        var details: [String: MemoryStarMapLeafDetail] = [:]
        
        // 1. 8 Orthogonal User KYC Dimensions
        if scope == .all || scope == .kyc {
            let activeMemories = memories.filter { !$0.isArchived }
            for dimension in KYCDimension.allCases {
                let items = activeMemories
                    .filter { $0.dimension == dimension }
                    .filter { item in
                        guard !needle.isEmpty else { return true }
                        return item.title.lowercased().contains(needle)
                            || item.detail.lowercased().contains(needle)
                            || item.factKey.lowercased().contains(needle)
                            || dimension.label.lowercased().contains(needle)
                    }
                guard !items.isEmpty else { continue }
                
                let clusterID = "kyc:\(dimension.rawValue)"
                let hex = Self.accentHex(for: dimension)
                let color = Color(hexString: hex)
                
                var leaves: [StarMapLeafNode] = []
                for record in items.prefix(40) {
                    let leafID = "kyc:\(record.id)"
                    let confPct = "\(Int((record.confidence * 100).rounded()))%"
                    let isMatch = !needle.isEmpty
                    leaves.append(
                        StarMapLeafNode(
                            id: leafID,
                            clusterID: clusterID,
                            title: record.title,
                            metaLine: "\(confPct) · \(record.source)",
                            statusBadge: record.isPinned ? AppLanguage.text("置顶", en: "Pinned") : nil,
                            dotColor: color,
                            weight: max(0.3, min(1.0, record.confidence)),
                            isHighlighted: isMatch || record.isPinned
                        )
                    )
                    details[leafID] = MemoryStarMapLeafDetail(
                        id: leafID,
                        clusterID: clusterID,
                        clusterTitle: dimension.label,
                        title: record.title,
                        subtitle: "\(dimension.label) · \(confPct)",
                        accentHex: hex,
                        primaryMetric: confPct,
                        badgeText: record.isPinned ? AppLanguage.text("核心画像", en: "Pinned") : nil,
                        bodyText: record.detail,
                        attributes: [
                            (AppLanguage.text("维度", en: "Dimension"), dimension.label),
                            (AppLanguage.text("置信度", en: "Confidence"), confPct),
                            (AppLanguage.text("强化次数", en: "Reinforced"), "\(record.reinforcementCount)"),
                            (AppLanguage.text("记录来源", en: "Source"), record.source),
                            (AppLanguage.text("事实键", en: "Key"), record.factKey),
                            (AppLanguage.text("更新时间", en: "Updated"), formatter.string(from: record.updatedAt)),
                        ]
                    )
                }
                
                clusters.append(
                    StarMapClusterNode(
                        id: clusterID,
                        title: dimension.label,
                        countText: "\(items.count)",
                        accent: color,
                        isCollapsed: collapsedClusterIDs.contains(clusterID),
                        leaves: leaves
                    )
                )
            }
        }
        
        // 2. Portable Structured Asset Clusters (Stocks · Podcasts · Blogs/RSS · X Creators)
        if scope == .all || scope == .assets {
            // Stocks
            let filteredStocks = stocks.filter { item in
                guard !needle.isEmpty else { return true }
                return item.symbol.lowercased().contains(needle)
                    || item.name.lowercased().contains(needle)
                    || item.thesisNote.lowercased().contains(needle)
            }
            if !filteredStocks.isEmpty {
                let clusterID = "asset:stocks"
                let hex = "#2563EB"
                let color = Color(hexString: hex)
                let title = AppLanguage.text("股票关注", en: "Stocks")
                let leaves: [StarMapLeafNode] = filteredStocks.prefix(40).map { stock in
                    let leafID = "stock:\(stock.instrumentID)"
                    let badge: String? = stock.lastChangePct.map { pct in
                        String(format: "%+.2f%%", pct)
                    }
                    let displayTitle = stock.name.isEmpty ? stock.symbol : stock.name
                    details[leafID] = MemoryStarMapLeafDetail(
                        id: leafID,
                        clusterID: clusterID,
                        clusterTitle: title,
                        title: displayTitle,
                        subtitle: stock.symbol,
                        accentHex: hex,
                        primaryMetric: stock.lastPrice.map { String(format: "%.2f", $0) },
                        badgeText: badge,
                        bodyText: stock.thesisNote,
                        attributes: [
                            (AppLanguage.text("代码", en: "Symbol"), stock.symbol),
                            (AppLanguage.text("市场", en: "Namespace"), stock.namespace),
                            (AppLanguage.text("来源", en: "Added By"), stock.addedBy),
                        ]
                    )
                    return StarMapLeafNode(
                        id: leafID,
                        clusterID: clusterID,
                        title: displayTitle,
                        metaLine: stock.symbol,
                        statusBadge: badge,
                        dotColor: color,
                        weight: 0.72,
                        isHighlighted: !needle.isEmpty
                    )
                }
                clusters.append(
                    StarMapClusterNode(
                        id: clusterID,
                        title: title,
                        countText: "\(filteredStocks.count)",
                        accent: color,
                        isCollapsed: collapsedClusterIDs.contains(clusterID),
                        leaves: leaves
                    )
                )
            }
            
            // Podcasts
            let filteredPodcasts = podcasts.filter { item in
                guard !needle.isEmpty else { return true }
                return item.title.lowercased().contains(needle)
                    || item.showName.lowercased().contains(needle)
                    || item.topicTag.lowercased().contains(needle)
            }
            if !filteredPodcasts.isEmpty {
                let clusterID = "asset:podcasts"
                let hex = "#9333EA"
                let color = Color(hexString: hex)
                let title = AppLanguage.text("播客订阅", en: "Podcasts")
                let leaves: [StarMapLeafNode] = filteredPodcasts.prefix(40).map { pod in
                    let leafID = "podcast:\(pod.id)"
                    details[leafID] = MemoryStarMapLeafDetail(
                        id: leafID,
                        clusterID: clusterID,
                        clusterTitle: title,
                        title: pod.title,
                        subtitle: pod.showName,
                        accentHex: hex,
                        primaryMetric: pod.platform,
                        badgeText: pod.topicTag.isEmpty ? nil : pod.topicTag,
                        bodyText: pod.notes,
                        attributes: [
                            (AppLanguage.text("节目", en: "Show"), pod.showName),
                            (AppLanguage.text("平台", en: "Platform"), pod.platform),
                            (AppLanguage.text("链接", en: "URL"), pod.sourceURL),
                        ]
                    )
                    return StarMapLeafNode(
                        id: leafID,
                        clusterID: clusterID,
                        title: pod.title,
                        metaLine: pod.showName.isEmpty ? pod.platform : pod.showName,
                        statusBadge: pod.topicTag.isEmpty ? nil : pod.topicTag,
                        dotColor: color,
                        weight: pod.isSaved ? 0.85 : 0.55,
                        isHighlighted: !needle.isEmpty || pod.isSaved
                    )
                }
                clusters.append(
                    StarMapClusterNode(
                        id: clusterID,
                        title: title,
                        countText: "\(filteredPodcasts.count)",
                        accent: color,
                        isCollapsed: collapsedClusterIDs.contains(clusterID),
                        leaves: leaves
                    )
                )
            }
            
            // Blogs / RSS Feeds
            let filteredFeeds = feeds.filter { item in
                guard !needle.isEmpty else { return true }
                return item.title.lowercased().contains(needle)
                    || item.author.lowercased().contains(needle)
                    || item.category.lowercased().contains(needle)
                    || item.siteURL.lowercased().contains(needle)
            }
            if !filteredFeeds.isEmpty {
                let clusterID = "asset:feeds"
                let hex = "#0D9488"
                let color = Color(hexString: hex)
                let title = AppLanguage.text("博客阅读", en: "Blogs")
                let leaves: [StarMapLeafNode] = filteredFeeds.prefix(40).map { feed in
                    let leafID = "feed:\(feed.id)"
                    let meta = feed.category.isEmpty ? feed.author : feed.category
                    details[leafID] = MemoryStarMapLeafDetail(
                        id: leafID,
                        clusterID: clusterID,
                        clusterTitle: title,
                        title: feed.title,
                        subtitle: meta,
                        accentHex: hex,
                        primaryMetric: feed.category.isEmpty ? nil : feed.category,
                        badgeText: feed.isPinned ? AppLanguage.text("置顶", en: "Pinned") : nil,
                        bodyText: feed.notes,
                        attributes: [
                            (AppLanguage.text("作者", en: "Author"), feed.author),
                            (AppLanguage.text("主页", en: "Site"), feed.siteURL),
                            (AppLanguage.text("RSS", en: "Feed"), feed.feedURL),
                        ]
                    )
                    return StarMapLeafNode(
                        id: leafID,
                        clusterID: clusterID,
                        title: feed.title,
                        metaLine: meta.isEmpty ? feed.siteURL : meta,
                        statusBadge: feed.isPinned ? AppLanguage.text("置顶", en: "Pinned") : nil,
                        dotColor: color,
                        weight: feed.isPinned ? 0.85 : 0.60,
                        isHighlighted: !needle.isEmpty || feed.isPinned
                    )
                }
                clusters.append(
                    StarMapClusterNode(
                        id: clusterID,
                        title: title,
                        countText: "\(filteredFeeds.count)",
                        accent: color,
                        isCollapsed: collapsedClusterIDs.contains(clusterID),
                        leaves: leaves
                    )
                )
            }
            
            // X Creators
            let filteredCreators = creators.filter { item in
                guard !needle.isEmpty else { return true }
                return item.handle.lowercased().contains(needle)
                    || item.displayName.lowercased().contains(needle)
                    || item.focusTags.lowercased().contains(needle)
                    || item.whyFollowing.lowercased().contains(needle)
            }
            if !filteredCreators.isEmpty {
                let clusterID = "asset:creators"
                let hex = "#D97706"
                let color = Color(hexString: hex)
                let title = AppLanguage.text("X 关注", en: "Creators")
                let leaves: [StarMapLeafNode] = filteredCreators.prefix(40).map { creator in
                    let leafID = "creator:\(creator.id)"
                    let handle = creator.handle.hasPrefix("@") ? creator.handle : "@\(creator.handle)"
                    let titleText = creator.displayName.isEmpty ? handle : creator.displayName
                    details[leafID] = MemoryStarMapLeafDetail(
                        id: leafID,
                        clusterID: clusterID,
                        clusterTitle: title,
                        title: titleText,
                        subtitle: handle,
                        accentHex: hex,
                        primaryMetric: creator.platform,
                        badgeText: creator.isPinned ? AppLanguage.text("置顶", en: "Pinned") : nil,
                        bodyText: creator.whyFollowing,
                        attributes: [
                            (AppLanguage.text("账号", en: "Handle"), handle),
                            (AppLanguage.text("标签", en: "Tags"), creator.focusTags),
                            (AppLanguage.text("主页", en: "Profile"), creator.profileURL),
                        ]
                    )
                    return StarMapLeafNode(
                        id: leafID,
                        clusterID: clusterID,
                        title: titleText,
                        metaLine: handle,
                        statusBadge: creator.focusTags.isEmpty ? nil : creator.focusTags,
                        dotColor: color,
                        weight: creator.isPinned ? 0.88 : 0.62,
                        isHighlighted: !needle.isEmpty || creator.isPinned
                    )
                }
                clusters.append(
                    StarMapClusterNode(
                        id: clusterID,
                        title: title,
                        countText: "\(filteredCreators.count)",
                        accent: color,
                        isCollapsed: collapsedClusterIDs.contains(clusterID),
                        leaves: leaves
                    )
                )
            }
        }
        
        return (clusters, details)
    }
    
    
    private static func accentHex(for dimension: KYCDimension) -> String {
        switch dimension {
            case .identity: "#3B82F6"
            case .cognition: "#6366F1"
            case .writingStyle: "#8B5CF6"
            case .goals: "#EC4899"
            case .finance: "#2563EB"
            case .informationDiet: "#0D9488"
            case .workflow: "#059669"
            case .taboos: "#EA580C"
        }
    }
}
