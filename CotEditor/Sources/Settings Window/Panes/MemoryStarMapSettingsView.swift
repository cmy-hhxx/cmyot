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


// MARK: - Multi-Level Preference Hierarchy Models

struct PreferenceDetailAttribute: Identifiable, Equatable, Sendable {
    let label: String
    let value: String
    var id: String { "\(self.label):\(self.value)" }
}

struct PreferenceItemNode: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let summaryTag: String?
    let secondaryMeta: String?
    let isPrimary: Bool
    let detailBody: String
    let attributes: [PreferenceDetailAttribute]
    
    var hasExpandableDetail: Bool {
        !self.detailBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !self.attributes.isEmpty
    }
}

struct PreferenceCategoryNode: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let symbolName: String
    let accentHex: String
    let items: [PreferenceItemNode]
}

struct PreferenceDomainNode: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let symbolName: String
    let accentHex: String
    let categories: [PreferenceCategoryNode]
    
    var totalItemCount: Int {
        self.categories.reduce(0) { $0 + $1.items.count }
    }
}


/// Hierarchical user preference browser inside Settings -> Preferences.
struct MemoryStarMapSettingsView: View {
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var memoryStore = CotMemoryStore.shared
    @State private var domains: [PreferenceDomainNode] = []
    @State private var expandedDomainIDs: Set<String> = []
    @State private var expandedCategoryIDs: Set<String> = []
    @State private var expandedItemIDs: Set<String> = []
    
    
    var body: some View {
        let isDark = (self.colorScheme == .dark)
        let cardSurface = isDark ? Color.white.opacity(0.055) : Color.white
        let cardBorder = isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
        let railColor = isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
        
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(self.domains) { domain in
                    self.domainSection(
                        domain: domain,
                        isDark: isDark,
                        cardSurface: cardSurface,
                        cardBorder: cardBorder,
                        railColor: railColor
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            self.memoryStore.reloadFromDatabase()
            self.rebuildHierarchy(initializeExpansion: self.domains.isEmpty)
        }
        .onChange(of: self.memoryStore.revision) { _, _ in
            self.rebuildHierarchy(initializeExpansion: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserProfileManager.activeProfileDidChangeNotification)) { _ in
            self.memoryStore.reloadFromDatabase()
            self.rebuildHierarchy(initializeExpansion: true)
        }
    }
    
    
    // MARK: - Level 1 Domain Card
    
    @ViewBuilder
    private func domainSection(
        domain: PreferenceDomainNode,
        isDark: Bool,
        cardSurface: Color,
        cardBorder: Color,
        railColor: Color
    ) -> some View {
        let accent = Color(hexString: domain.accentHex)
        let isExpanded = self.expandedDomainIDs.contains(domain.id)
        
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    if isExpanded {
                        self.expandedDomainIDs.remove(domain.id)
                    } else {
                        self.expandedDomainIDs.insert(domain.id)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(accent.opacity(isDark ? 0.22 : 0.12))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: domain.symbolName)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(accent)
                        )
                    
                    Text(domain.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer(minLength: 8)
                    
                    Text("\(domain.categories.count) · \(domain.totalItemCount)")
                        .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(isDark ? 0.08 : 0.045), in: Capsule())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            if isExpanded {
                Rectangle()
                    .fill(cardBorder)
                    .frame(height: 1)
                    .padding(.horizontal, 14)
                
                if domain.categories.isEmpty {
                    Text(AppLanguage.text("暂无记录条目", en: "No entries yet"))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 38)
                        .padding(.vertical, 12)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(domain.categories) { category in
                            self.categoryBranch(
                                category: category,
                                isDark: isDark,
                                railColor: railColor
                            )
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .padding(.horizontal, 14)
                }
            }
        }
        .background(cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        )
    }
    
    
    // MARK: - Level 2 Sub-Category Branch
    
    @ViewBuilder
    private func categoryBranch(
        category: PreferenceCategoryNode,
        isDark: Bool,
        railColor: Color
    ) -> some View {
        let accent = Color(hexString: category.accentHex)
        let isExpanded = self.expandedCategoryIDs.contains(category.id)
        
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isExpanded {
                        self.expandedCategoryIDs.remove(category.id)
                    } else {
                        self.expandedCategoryIDs.insert(category.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                    
                    Circle()
                        .fill(accent)
                        .frame(width: 7, height: 7)
                    
                    Image(systemName: category.symbolName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accent)
                    
                    Text(category.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer(minLength: 8)
                    
                    Text("\(category.items.count)")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isDark ? 0.04 : 0.025))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            if isExpanded {
                HStack(alignment: .top, spacing: 0) {
                    Rectangle()
                        .fill(railColor)
                        .frame(width: 1.5)
                        .padding(.leading, 13)
                        .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(category.items) { item in
                            self.itemNodeRow(
                                item: item,
                                accent: accent,
                                isDark: isDark,
                                railColor: railColor
                            )
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    
    // MARK: - Level 3 Preference Item & Level 4 Detail Drawer
    
    @ViewBuilder
    private func itemNodeRow(
        item: PreferenceItemNode,
        accent: Color,
        isDark: Bool,
        railColor: Color
    ) -> some View {
        let canExpand = item.hasExpandableDetail
        let isExpanded = canExpand && self.expandedItemIDs.contains(item.id)
        
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard canExpand else { return }
                withAnimation(.easeOut(duration: 0.14)) {
                    if isExpanded {
                        self.expandedItemIDs.remove(item.id)
                    } else {
                        self.expandedItemIDs.insert(item.id)
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if canExpand {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 11)
                    } else {
                        Circle()
                            .fill(accent.opacity(0.75))
                            .frame(width: 5, height: 5)
                            .frame(width: 11)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 12.5, weight: item.isPrimary ? .semibold : .medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        
                        if let secondary = item.secondaryMeta, !secondary.isEmpty {
                            Text(secondary)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    Spacer(minLength: 8)
                    
                    if let badge = item.summaryTag, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(accent.opacity(isDark ? 0.16 : 0.10), in: Capsule())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isExpanded ? accent.opacity(isDark ? 0.10 : 0.05) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(canExpand ? .link : .default)
            
            if isExpanded {
                HStack(alignment: .top, spacing: 0) {
                    Rectangle()
                        .fill(accent.opacity(0.35))
                        .frame(width: 1.5)
                        .padding(.leading, 14)
                        .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        let cleanBody = item.detailBody.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleanBody.isEmpty {
                            Text(cleanBody)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary.opacity(0.88))
                                .lineSpacing(3.5)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        
                        if !item.attributes.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(item.attributes) { attr in
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(attr.label)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 68, alignment: .leading)
                                        
                                        Text(attr.value)
                                            .font(.system(size: 11, design: .rounded))
                                            .foregroundStyle(.primary.opacity(0.85))
                                            .fixedSize(horizontal: false, vertical: true)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.primary.opacity(isDark ? 0.045 : 0.03))
                            )
                        }
                    }
                    .padding(.leading, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                }
            }
        }
    }
    
    
    // MARK: - Hierarchy Construction
    
    private func rebuildHierarchy(initializeExpansion: Bool) {
        let built = Self.buildPreferenceDomains(
            memories: self.memoryStore.memories,
            stocks: self.memoryStore.stocks,
            podcasts: self.memoryStore.podcasts,
            feeds: self.memoryStore.feeds,
            creators: self.memoryStore.creators
        )
        self.domains = built
        if initializeExpansion {
            self.expandedDomainIDs = Set(built.map(\.id))
            self.expandedCategoryIDs = Set(built.flatMap(\.categories).map(\.id))
            self.expandedItemIDs = Set(
                built.flatMap(\.categories)
                    .flatMap(\.items)
                    .filter { $0.isPrimary && $0.hasExpandableDetail }
                    .map(\.id)
            )
        }
    }
    
    
    private static let updatedTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
    
    
    static func buildPreferenceDomains(
        memories: [UserKYCMemoryRecord],
        stocks: [WatchlistStockRecord],
        podcasts: [StoredPodcastRecord],
        feeds: [FollowedFeedRecord],
        creators: [FollowedCreatorRecord]
    ) -> [PreferenceDomainNode] {
        let formatter = Self.updatedTimestampFormatter
        
        let activeMemories = memories.filter { !$0.isArchived }
        func kycCategory(for dimension: KYCDimension) -> PreferenceCategoryNode? {
            let items = activeMemories
                .filter { $0.dimension == dimension }
                .sorted { lhs, rhs in
                    if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                    return lhs.updatedAt > rhs.updatedAt
                }
            guard !items.isEmpty else { return nil }
            let nodes: [PreferenceItemNode] = items.map { record in
                let confPct = "\(Int((record.confidence * 100).rounded()))%"
                var attrs: [PreferenceDetailAttribute] = [
                    PreferenceDetailAttribute(label: AppLanguage.text("置信度", en: "Confidence"), value: confPct),
                    PreferenceDetailAttribute(label: AppLanguage.text("强化次数", en: "Reinforced"), value: "\(record.reinforcementCount)"),
                    PreferenceDetailAttribute(label: AppLanguage.text("来源", en: "Source"), value: record.source),
                    PreferenceDetailAttribute(label: AppLanguage.text("键名", en: "Key"), value: record.factKey),
                    PreferenceDetailAttribute(label: AppLanguage.text("更新时间", en: "Updated"), value: formatter.string(from: record.updatedAt)),
                ]
                if let ref = record.evidenceRef, !ref.isEmpty {
                    attrs.append(PreferenceDetailAttribute(label: AppLanguage.text("依据", en: "Evidence"), value: ref))
                }
                return PreferenceItemNode(
                    id: "kyc:\(record.id)",
                    title: record.title,
                    summaryTag: record.isPinned ? AppLanguage.text("核心", en: "Core") : confPct,
                    secondaryMeta: nil,
                    isPrimary: record.isPinned,
                    detailBody: record.detail,
                    attributes: attrs
                )
            }
            return PreferenceCategoryNode(
                id: "cat:kyc:\(dimension.rawValue)",
                title: dimension.label,
                symbolName: dimension.symbolName,
                accentHex: Self.accentHex(for: dimension),
                items: nodes
            )
        }
        
        // Domain 1: 创作与表达偏好
        let expressionCategories: [PreferenceCategoryNode] = [
            kycCategory(for: .writingStyle),
            kycCategory(for: .workflow),
            kycCategory(for: .taboos),
        ].compactMap { $0 }
        
        // Domain 2: 个人认知与目标
        let cognitionCategories: [PreferenceCategoryNode] = [
            kycCategory(for: .identity),
            kycCategory(for: .cognition),
            kycCategory(for: .goals),
        ].compactMap { $0 }
        
        // Domain 3: 信息与关注偏好
        var interestCategories: [PreferenceCategoryNode] = [
            kycCategory(for: .informationDiet),
            kycCategory(for: .finance),
        ].compactMap { $0 }
        
        if !stocks.isEmpty {
            let stockItems = stocks.map { stock in
                let displayTitle = stock.name.isEmpty ? stock.symbol : stock.name
                let changeBadge = stock.lastChangePct.map { String(format: "%+.2f%%", $0) }
                return PreferenceItemNode(
                    id: "stock:\(stock.instrumentID)",
                    title: displayTitle,
                    summaryTag: changeBadge ?? stock.symbol,
                    secondaryMeta: stock.symbol,
                    isPrimary: false,
                    detailBody: stock.thesisNote,
                    attributes: [
                        PreferenceDetailAttribute(label: AppLanguage.text("代码", en: "Symbol"), value: stock.symbol),
                        PreferenceDetailAttribute(label: AppLanguage.text("市场", en: "Market"), value: stock.namespace),
                        PreferenceDetailAttribute(label: AppLanguage.text("来源", en: "Added By"), value: stock.addedBy),
                    ]
                )
            }
            interestCategories.append(PreferenceCategoryNode(
                id: "cat:asset:stocks",
                title: AppLanguage.text("关注标的", en: "Watchlist"),
                symbolName: "chart.line.uptrend.xyaxis",
                accentHex: "#2563EB",
                items: stockItems
            ))
        }
        
        if !podcasts.isEmpty {
            let podItems = podcasts.map { pod in
                var attrs = [
                    PreferenceDetailAttribute(label: AppLanguage.text("平台", en: "Platform"), value: pod.platform),
                ]
                if !pod.showName.isEmpty {
                    attrs.append(PreferenceDetailAttribute(label: AppLanguage.text("节目", en: "Show"), value: pod.showName))
                }
                if !pod.sourceURL.isEmpty {
                    attrs.append(PreferenceDetailAttribute(label: AppLanguage.text("链接", en: "URL"), value: pod.sourceURL))
                }
                return PreferenceItemNode(
                    id: "podcast:\(pod.id)",
                    title: pod.title,
                    summaryTag: pod.topicTag.isEmpty ? pod.platform : pod.topicTag,
                    secondaryMeta: pod.showName.isEmpty ? pod.platform : pod.showName,
                    isPrimary: pod.isSaved,
                    detailBody: pod.notes,
                    attributes: attrs
                )
            }
            interestCategories.append(PreferenceCategoryNode(
                id: "cat:asset:podcasts",
                title: AppLanguage.text("播客节目", en: "Podcasts"),
                symbolName: "mic.fill",
                accentHex: "#9333EA",
                items: podItems
            ))
        }
        
        if !feeds.isEmpty {
            let feedItems = feeds.map { feed in
                var attrs: [PreferenceDetailAttribute] = []
                if !feed.author.isEmpty {
                    attrs.append(PreferenceDetailAttribute(label: AppLanguage.text("作者", en: "Author"), value: feed.author))
                }
                if !feed.siteURL.isEmpty {
                    attrs.append(PreferenceDetailAttribute(label: AppLanguage.text("主页", en: "Site"), value: feed.siteURL))
                }
                if !feed.feedURL.isEmpty {
                    attrs.append(PreferenceDetailAttribute(label: "RSS", value: feed.feedURL))
                }
                return PreferenceItemNode(
                    id: "feed:\(feed.id)",
                    title: feed.title,
                    summaryTag: feed.isPinned ? AppLanguage.text("置顶", en: "Pinned") : (feed.category.isEmpty ? nil : feed.category),
                    secondaryMeta: feed.author.isEmpty ? feed.siteURL : feed.author,
                    isPrimary: feed.isPinned,
                    detailBody: feed.notes,
                    attributes: attrs
                )
            }
            interestCategories.append(PreferenceCategoryNode(
                id: "cat:asset:feeds",
                title: AppLanguage.text("订阅博客", en: "Feeds"),
                symbolName: "dot.radiowaves.left.and.right",
                accentHex: "#0D9488",
                items: feedItems
            ))
        }
        
        if !creators.isEmpty {
            let creatorItems = creators.map { creator in
                let handle = creator.handle.hasPrefix("@") ? creator.handle : "@\(creator.handle)"
                let title = creator.displayName.isEmpty ? handle : creator.displayName
                var attrs = [
                    PreferenceDetailAttribute(label: AppLanguage.text("账号", en: "Handle"), value: handle),
                ]
                if !creator.focusTags.isEmpty {
                    attrs.append(PreferenceDetailAttribute(label: AppLanguage.text("领域", en: "Focus"), value: creator.focusTags))
                }
                if !creator.profileURL.isEmpty {
                    attrs.append(PreferenceDetailAttribute(label: AppLanguage.text("主页", en: "Profile"), value: creator.profileURL))
                }
                return PreferenceItemNode(
                    id: "creator:\(creator.id)",
                    title: title,
                    summaryTag: creator.focusTags.isEmpty ? nil : creator.focusTags,
                    secondaryMeta: handle,
                    isPrimary: creator.isPinned,
                    detailBody: creator.whyFollowing,
                    attributes: attrs
                )
            }
            interestCategories.append(PreferenceCategoryNode(
                id: "cat:asset:creators",
                title: AppLanguage.text("关注创作者", en: "Creators"),
                symbolName: "person.2.fill",
                accentHex: "#D97706",
                items: creatorItems
            ))
        }
        
        return [
            PreferenceDomainNode(
                id: "domain:expression",
                title: AppLanguage.text("创作风格与表达习惯", en: "Writing & Workflow Preferences"),
                symbolName: "pencil.and.outline",
                accentHex: "#7C3AED",
                categories: expressionCategories
            ),
            PreferenceDomainNode(
                id: "domain:cognition",
                title: AppLanguage.text("身份背景与思维偏好", en: "Identity & Cognitive Profile"),
                symbolName: "brain.head.profile",
                accentHex: "#2563EB",
                categories: cognitionCategories
            ),
            PreferenceDomainNode(
                id: "domain:interests",
                title: AppLanguage.text("关注领域与信息食谱", en: "Interests & Information Diet"),
                symbolName: "safari",
                accentHex: "#0D9488",
                categories: interestCategories
            ),
        ]
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
        let formatter = Self.updatedTimestampFormatter
        
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
