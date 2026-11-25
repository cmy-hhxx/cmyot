//
//  PodcastBoardView.swift
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

private enum PodcastBoardFilter: String, CaseIterable, Identifiable {
    
    case discover
    case saved
    case downloaded
    case history
    
    var id: String { self.rawValue }
    
    var label: String {
        switch self {
            case .discover: AppLanguage.text("探索", en: "Discover")
            case .saved: AppLanguage.text("收藏", en: "Saved")
            case .downloaded: AppLanguage.text("已下载", en: "Offline")
            case .history: AppLanguage.text("历史", en: "History")
        }
    }
}


/// Embedded Podcast Search, Offline Downloader, Agent Bot Curator, & Collapsible/Immersive Stage
/// (drawing interaction patterns from PodLilt, Airmedy, and PodPin).
struct PodcastBoardView: View {
    
    @Binding var boardState: PaneBoardState
    let tokens: StudioColorTokens
    var surfaceColor: Color? = nil
    var hasCustomBackground: Bool = false
    var onRevertToDocument: (() -> Void)? = nil
    var onOpenNote: ((String, String) -> Void)?
    
    @State private var podcastService = CotPodcastService.shared
    @State private var artworkColor = PodcastArtworkColorModel()
    @State private var filter: PodcastBoardFilter = .discover
    @State private var layoutMode: PodcastLayoutMode = .split
    @State private var isTopToolbarCollapsed: Bool = false
    @State private var isShowingShowNotes: Bool = false
    @State private var isShowingBotFinderPopover: Bool = false
    @State private var botTopicInput: String = ""
    @State private var isBotSearching: Bool = false
    @State private var searchInput: String = ""
    @State private var isScrubbing = false
    @State private var isHoveringTrack = false
    @State private var draftSeekTime: TimeInterval = 0
    @State private var hoverTime: TimeInterval?
    @State private var hoveredEpisodeID: String?
    
    private static let starterChips = ["大模型训练", "心理与自我", "商业思考", "科技人文"]
    
    private var canvasBackground: Color {
        self.surfaceColor ?? self.tokens.canvasTop
    }
    
    private var secondaryInk: Color {
        self.tokens.isDark
            ? Color(red: 0.62, green: 0.65, blue: 0.72)
            : Color(red: 0.34, green: 0.37, blue: 0.44)
    }
    
    private var mutedInk: Color {
        self.tokens.isDark
            ? Color(red: 0.46, green: 0.50, blue: 0.57)
            : Color(red: 0.48, green: 0.52, blue: 0.58)
    }
    
    private var displayedEpisodes: [PodcastEpisodeItem] {
        switch self.filter {
            case .discover:
                return self.podcastService.searchResults.isEmpty
                    ? self.podcastService.savedEpisodes.map(PodcastEpisodeItem.init(record:))
                    : self.podcastService.searchResults
            case .saved:
                return self.podcastService.savedEpisodes.map(PodcastEpisodeItem.init(record:))
            case .downloaded:
                return self.podcastService.downloadedEpisodes
            case .history:
                return self.podcastService.historyEpisodes.map(PodcastEpisodeItem.init(record:))
        }
    }
    
    private var effectiveChips: [String] {
        self.boardState.topicChips.isEmpty ? Self.starterChips : self.boardState.topicChips
    }
    
    
    var body: some View {
        let hasPlayer = (self.podcastService.currentEpisode != nil)
        
        VStack(spacing: 0) {
            if self.layoutMode != .immersive {
                if self.isTopToolbarCollapsed {
                    self.collapsedTopStrip
                } else {
                    self.topControlBar
                }
                
                Rectangle()
                    .fill(self.tokens.hairline)
                    .frame(height: 1)
            }
            
            if self.layoutMode != .immersive,
               let reminder = self.podcastService.unreadReminders.first
            {
                self.agentReminderBanner(reminder)
                Rectangle()
                    .fill(self.tokens.hairline)
                    .frame(height: 1)
            }
            
            GeometryReader { geo in
                let isWide = geo.size.width >= 640
                
                if self.layoutMode == .immersive, hasPlayer {
                    self.immersivePlayerStage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                } else if self.layoutMode == .compactMini || !hasPlayer {
                    ZStack(alignment: .bottom) {
                        self.episodeListStage
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.bottom, hasPlayer ? 64 : 0)
                        
                        if hasPlayer {
                            self.compactMiniPlayerBar
                                .padding(.horizontal, 12)
                                .padding(.bottom, 10)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                } else if isWide {
                    HStack(spacing: 0) {
                        self.playerStage
                            .frame(width: min(360, max(275, geo.size.width * 0.40)))
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Rectangle()
                            .fill(self.tokens.hairline)
                            .frame(width: 1)
                        self.episodeListStage
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        self.playerStage
                            .frame(height: min(295, max(224, geo.size.height * 0.46)))
                            .transition(.move(edge: .top).combined(with: .opacity))
                        Rectangle()
                            .fill(self.tokens.hairline)
                            .frame(height: 1)
                        self.episodeListStage
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24), value: self.podcastService.currentEpisode?.id)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24), value: self.layoutMode)
        }
        .background(self.hasCustomBackground ? Color.clear : self.canvasBackground)
        .onAppear {
            self.syncFromBoardState()
        }
        .onChange(of: self.boardState.query) { _, _ in
            self.syncFromBoardState()
        }
        .onChange(of: self.boardState.topicChips) { _, _ in
            self.syncFromBoardState()
        }
        .onChange(of: self.podcastService.currentEpisode?.artworkURL) { _, newURL in
            self.artworkColor.load(from: newURL)
        }
    }
    
    
    // MARK: - Top Control Bars (Expanded & Collapsible)
    
    private var topControlBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(self.mutedInk)
                TextField("", text: self.$searchInput, prompt: Text(AppLanguage.text("话题关键词 / 小宇宙 / B 站链接", en: "Topic or Podcast URL")))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(self.tokens.primaryInk)
                    .onSubmit {
                        let q = self.searchInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !q.isEmpty else { return }
                        self.filter = .discover
                        self.boardState.query = q
                        self.boardState.dynamicTitle = q.hasPrefix("http") ? nil : q
                        Task {
                            await self.podcastService.searchAndRecommend(for: [q], autoplayFirst: true)
                        }
                    }
                if !self.searchInput.isEmpty {
                    Button {
                        self.searchInput = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(self.mutedInk)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(self.tokens.inset, in: Capsule())
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(self.effectiveChips, id: \.self) { chip in
                        let selected = (self.boardState.query == chip)
                        Button {
                            self.filter = .discover
                            self.searchInput = chip
                            self.boardState.query = chip
                            Task {
                                await self.podcastService.searchAndRecommend(for: [chip], autoplayFirst: false)
                            }
                        } label: {
                            Text(chip)
                                .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? self.tokens.onAccentInk : self.secondaryInk)
                                .padding(.horizontal, 9)
                                .frame(height: 23)
                                .background(selected ? self.tokens.accent : self.tokens.inset, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
            }
            .frame(maxWidth: 230)
            
            Spacer(minLength: 4)
            
            // Agent Bot Discovery & Offline Download trigger
            Button {
                self.isShowingBotFinderPopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: self.isBotSearching ? "hourglass" : "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    Text(AppLanguage.text("Bot找播客", en: "Bot Curate"))
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(self.tokens.accentText)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(self.tokens.accent.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help(AppLanguage.text("让 Bot 帮我搜寻并下载知识播客，准备好后提醒收听", en: "Ask Bot to find & download a podcast"))
            .popover(isPresented: self.$isShowingBotFinderPopover, arrowEdge: .bottom) {
                self.botFinderPopover
            }
            
            HStack(spacing: 2) {
                ForEach(PodcastBoardFilter.allCases) { tab in
                    let active = (self.filter == tab)
                    Button {
                        withAnimation(.easeOut(duration: 0.14)) {
                            self.filter = tab
                        }
                    } label: {
                        Text(tab.label)
                            .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? self.tokens.onAccentInk : self.secondaryInk)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(active ? self.tokens.accent : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(2)
            .background(self.tokens.inset, in: Capsule())
            
            if self.podcastService.currentEpisode != nil {
                HStack(spacing: 2) {
                    ForEach(PodcastLayoutMode.allCases) { mode in
                        let active = (self.layoutMode == mode)
                        Button {
                            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                                self.layoutMode = mode
                            }
                        } label: {
                            Image(systemName: mode.symbolName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(active ? self.tokens.onAccentInk : self.mutedInk)
                                .frame(width: 24, height: 22)
                                .background(active ? self.tokens.accent : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .help(mode.label)
                    }
                }
                .padding(2)
                .background(self.tokens.inset, in: Capsule())
            }
            
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    self.isTopToolbarCollapsed = true
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(self.mutedInk)
                    .frame(width: 22, height: 24)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help(AppLanguage.text("收起顶部栏", en: "Collapse Toolbar"))
            
            if let onRevertToDocument = self.onRevertToDocument {
                Button(action: onRevertToDocument) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(self.mutedInk)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(AppLanguage.text("切换回文档", en: "Back to Document"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }
    
    
    private var collapsedTopStrip: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    self.isTopToolbarCollapsed = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text(AppLanguage.text("展开播客栏", en: "Expand Bar"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(self.secondaryInk)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(self.tokens.inset, in: Capsule())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            Spacer()
            
            if self.podcastService.currentEpisode != nil {
                Button {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                        self.layoutMode = .immersive
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles.tv")
                            .font(.system(size: 10.5))
                        Text(AppLanguage.text("沉浸模式", en: "Focus Mode"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(self.tokens.accentText)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(self.tokens.accent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
    }
    
    
    // MARK: - Bot Discovery Popover & Reminder Banner
    
    private var botFinderPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLanguage.text("Bot 找播客", en: "Find & Download Podcast"))
                .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 6) {
                TextField(
                    AppLanguage.text("例如：大模型训练", en: "e.g., LLM pretraining"),
                    text: self.$botTopicInput
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit {
                    self.triggerBotDiscovery()
                }
                
                Button {
                    self.triggerBotDiscovery()
                } label: {
                    Text(AppLanguage.text("找并下载", en: "Find"))
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.botTopicInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || self.isBotSearching)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["大模型训练", "强化学习前沿", "化合物半导体", "深度阅读习惯"], id: \.self) { tag in
                        Button {
                            self.botTopicInput = tag
                        } label: {
                            Text(tag)
                                .font(.system(size: 11))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 340)
    }
    
    
    private func triggerBotDiscovery() {
        let topic = self.botTopicInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else { return }
        self.isBotSearching = true
        self.isShowingBotFinderPopover = false
        Task {
            _ = await self.podcastService.agentDiscoverDownloadAndRemind(topic: topic, openBoard: false)
            self.isBotSearching = false
            self.filter = .discover
        }
    }
    
    
    private func agentReminderBanner(_ rec: AgentPodcastRecommendation) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 13))
                .foregroundStyle(self.tokens.accent)
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(AppLanguage.text("Bot 播客已备好", en: "Bot Curated"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(self.tokens.accentText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(self.tokens.accent.opacity(0.14), in: Capsule())
                    
                    Text(rec.episodeTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineLimit(1)
                }
                Text(rec.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(self.secondaryInk)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 6)
            
            Button {
                self.podcastService.markReminderRead(id: rec.id)
                if let ep = self.findEpisode(id: rec.episodeID) {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) {
                        self.layoutMode = .immersive
                    }
                    self.podcastService.loadAndPlay(episode: ep, autoplay: true)
                }
            } label: {
                Text(AppLanguage.text("沉浸收听", en: "Listen Now"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(self.tokens.onAccentInk)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(self.tokens.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            Button {
                self.podcastService.markReminderRead(id: rec.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(self.mutedInk)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(self.tokens.accent.opacity(self.tokens.isDark ? 0.12 : 0.07))
    }
    
    
    // MARK: - Split Player Stage
    
    private var playerStage: some View {
        let episode = self.podcastService.currentEpisode
        let duration = max(self.podcastService.duration, episode?.duration ?? 0, 1)
        let displayedTime = self.isScrubbing ? self.draftSeekTime : self.podcastService.currentTime
        
        return ZStack {
            if let ambient = self.artworkColor.color {
                ambient.opacity(self.tokens.isDark ? 0.18 : 0.08)
            } else {
                Color.primary.opacity(self.tokens.isDark ? 0.03 : 0.015)
            }
            
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    if let episode, self.podcastService.isDownloaded(episode) {
                        Label(AppLanguage.text("离线已缓存", en: "Offline"), systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(self.tokens.accentText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(self.tokens.accent.opacity(0.12), in: Capsule())
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                            self.layoutMode = .immersive
                        }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(self.secondaryInk)
                            .frame(width: 24, height: 24)
                            .background(self.tokens.inset, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(AppLanguage.text("进入全屏沉浸收听", en: "Focus Mode"))
                    
                    Button {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                            self.layoutMode = .compactMini
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(self.secondaryInk)
                            .frame(width: 24, height: 24)
                            .background(self.tokens.inset, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(AppLanguage.text("折叠为迷你播放器", en: "Collapse to Mini Bar"))
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                
                Spacer(minLength: 2)
                
                self.artworkTile(urlString: episode?.artworkURL, size: 132, cornerRadius: 14)
                
                VStack(spacing: 4) {
                    Text(episode?.title ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    
                    if let show = episode?.showName, !show.isEmpty {
                        Text(show)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(self.secondaryInk)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 18)
                
                VStack(spacing: 6) {
                    self.capsuleScrubBar(current: displayedTime, duration: duration)
                    
                    HStack {
                        Text(PodcastTimeFormatter.string(for: self.hoverTime ?? displayedTime))
                            .foregroundStyle(self.hoverTime != nil ? self.tokens.accentText : self.mutedInk)
                        Spacer()
                        Text(PodcastTimeFormatter.remainingString(current: displayedTime, duration: duration))
                            .foregroundStyle(self.mutedInk)
                    }
                    .font(.system(size: 10.5).monospacedDigit())
                }
                .padding(.horizontal, 22)
                
                self.playbackControlsRow(episode: episode, displayedTime: displayedTime)
                
                Spacer(minLength: 6)
            }
        }
    }
    
    
    // MARK: - Immersive Focus Listening Stage (Airmedy / PodLilt Inspired)
    
    private var immersivePlayerStage: some View {
        let episode = self.podcastService.currentEpisode
        let duration = max(self.podcastService.duration, episode?.duration ?? 0, 1)
        let displayedTime = self.isScrubbing ? self.draftSeekTime : self.podcastService.currentTime
        let cleanNotes = episode.map { Self.plainTextSummary(from: $0.summary) } ?? ""
        
        return ZStack {
            if let ambient = self.artworkColor.color {
                LinearGradient(
                    colors: [
                        ambient.opacity(self.tokens.isDark ? 0.42 : 0.20),
                        ambient.opacity(self.tokens.isDark ? 0.14 : 0.05),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.primary.opacity(self.tokens.isDark ? 0.04 : 0.02)
            }
            
            VStack(spacing: 0) {
                // Top Focus Navigation Bar
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                            self.layoutMode = .split
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                            Text(AppLanguage.text("退出沉浸", en: "Exit Focus"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(self.secondaryInk)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(self.tokens.inset, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    Button {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                            self.layoutMode = .compactMini
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "dock.rectangle")
                                .font(.system(size: 11, weight: .medium))
                            Text(AppLanguage.text("迷你条", en: "Mini Bar"))
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(self.secondaryInk)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(self.tokens.inset, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    Spacer()
                    
                    if !cleanNotes.isEmpty {
                        Button {
                            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)) {
                                self.isShowingShowNotes.toggle()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 11, weight: .medium))
                                Text(AppLanguage.text("单集简介", en: "Show Notes"))
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(self.isShowingShowNotes ? self.tokens.onAccentInk : self.secondaryInk)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(self.isShowingShowNotes ? self.tokens.accent : self.tokens.inset, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                    
                    if let onRevertToDocument = self.onRevertToDocument {
                        Button(action: onRevertToDocument) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(self.secondaryInk)
                                .frame(width: 28, height: 28)
                                .background(self.tokens.inset, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                
                HStack(spacing: 28) {
                    VStack(spacing: 18) {
                        Spacer(minLength: 8)
                        
                        self.artworkTile(urlString: episode?.artworkURL, size: 196, cornerRadius: 20)
                            .scaleEffect(self.podcastService.phase.isPlaying ? 1.0 : 0.95)
                            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: self.podcastService.phase.isPlaying)
                        
                        VStack(spacing: 6) {
                            if let episode, self.podcastService.isDownloaded(episode) {
                                Label(AppLanguage.text("本地离线音频", en: "Offline Audio Ready"), systemImage: "checkmark.seal.fill")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(self.tokens.accentText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(self.tokens.accent.opacity(0.14), in: Capsule())
                            }
                            
                            Text(episode?.title ?? "")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(self.tokens.primaryInk)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: 420)
                            
                            if let show = episode?.showName, !show.isEmpty {
                                Text(show)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(self.secondaryInk)
                            }
                        }
                        
                        VStack(spacing: 6) {
                            self.capsuleScrubBar(current: displayedTime, duration: duration)
                            HStack {
                                Text(PodcastTimeFormatter.string(for: self.hoverTime ?? displayedTime))
                                    .foregroundStyle(self.hoverTime != nil ? self.tokens.accentText : self.mutedInk)
                                Spacer()
                                Text(PodcastTimeFormatter.remainingString(current: displayedTime, duration: duration))
                                    .foregroundStyle(self.mutedInk)
                            }
                            .font(.system(size: 11).monospacedDigit())
                        }
                        .frame(maxWidth: 420)
                        
                        self.playbackControlsRow(episode: episode, displayedTime: displayedTime, includeSleepAndVolume: true)
                        
                        Spacer(minLength: 10)
                    }
                    .frame(maxWidth: .infinity)
                    
                    if self.isShowingShowNotes && !cleanNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(AppLanguage.text("节目简介 / Shownotes", en: "Show Notes"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(self.tokens.primaryInk)
                            
                            ScrollView {
                                Text(cleanNotes)
                                    .font(.system(size: 12.5))
                                    .lineSpacing(5)
                                    .foregroundStyle(self.secondaryInk)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(16)
                        .frame(width: 280)
                        .frame(maxHeight: 380)
                        .background(self.tokens.card.opacity(0.86), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(self.tokens.hairline, lineWidth: 0.8)
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
    
    
    // MARK: - Compact Floating Mini Bar (PodLilt Style)
    
    private var compactMiniPlayerBar: some View {
        let episode = self.podcastService.currentEpisode
        let duration = max(self.podcastService.duration, episode?.duration ?? 0, 1)
        let ratio = min(1.0, max(0.0, self.podcastService.currentTime / duration))
        
        return VStack(spacing: 0) {
            GeometryReader { geo in
                Rectangle()
                    .fill(self.tokens.accent)
                    .frame(width: geo.size.width * CGFloat(ratio), height: 2.5)
            }
            .frame(height: 2.5)
            
            HStack(spacing: 10) {
                self.artworkTile(urlString: episode?.artworkURL, size: 36, cornerRadius: 7)
                    .onTapGesture {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                            self.layoutMode = .immersive
                        }
                    }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(episode?.title ?? "")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if let show = episode?.showName, !show.isEmpty {
                            Text(show).lineLimit(1)
                        }
                        Text("· \(PodcastTimeFormatter.string(for: self.podcastService.currentTime)) / \(PodcastTimeFormatter.string(for: duration))")
                            .monospacedDigit()
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(self.secondaryInk)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                        self.layoutMode = .immersive
                    }
                }
                
                Spacer(minLength: 6)
                
                Button {
                    self.podcastService.skipBackward()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(self.secondaryInk)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                
                Button {
                    self.podcastService.togglePlayback()
                } label: {
                    ZStack {
                        Circle()
                            .fill(self.tokens.accent)
                            .frame(width: 30, height: 30)
                        Image(systemName: self.podcastService.phase.hasPlaybackIntent ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(self.tokens.onAccentInk)
                    }
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button {
                    self.podcastService.skipForward()
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(self.secondaryInk)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                
                Button {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                        self.layoutMode = .immersive
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(self.secondaryInk)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(AppLanguage.text("展开沉浸模式", en: "Expand Focus View"))
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(self.tokens.hairlineStrong, lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(self.tokens.isDark ? 0.32 : 0.12), radius: 12, y: 4)
    }
    
    
    // MARK: - Shared Player Controls
    
    private func playbackControlsRow(
        episode: PodcastEpisodeItem?,
        displayedTime: TimeInterval,
        includeSleepAndVolume: Bool = false
    ) -> some View {
        let isSaved = episode.map { self.podcastService.isSaved($0.id) } ?? false
        let isDownloaded = episode.map { self.podcastService.isDownloaded($0) } ?? false
        
        return VStack(spacing: 10) {
            HStack(spacing: 14) {
                Menu {
                    ForEach(CotPodcastService.supportedRates, id: \.self) { r in
                        Button("\(r.formatted(.number.precision(.fractionLength(0...2))))×") {
                            self.podcastService.setRate(r)
                        }
                    }
                } label: {
                    Text("\(self.podcastService.rate.formatted(.number.precision(.fractionLength(0...2))))×")
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(self.secondaryInk)
                        .frame(width: 34, height: 30)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                
                Button {
                    self.podcastService.skipBackward()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 16.5, weight: .medium))
                        .foregroundStyle(self.tokens.primaryInk)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button {
                    self.podcastService.togglePlayback()
                } label: {
                    ZStack {
                        Circle()
                            .fill(self.tokens.accent)
                            .frame(width: 44, height: 44)
                        if self.podcastService.phase == .loading || self.podcastService.phase == .buffering {
                            ProgressView()
                                .controlSize(.small)
                                .tint(self.tokens.onAccentInk)
                        } else {
                            Image(systemName: self.podcastService.phase.hasPlaybackIntent ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(self.tokens.onAccentInk)
                        }
                    }
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button {
                    self.podcastService.skipForward()
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 16.5, weight: .medium))
                        .foregroundStyle(self.tokens.primaryInk)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                if let episode {
                    Button {
                        Task { _ = await self.podcastService.downloadEpisode(episode) }
                    } label: {
                        Image(systemName: isDownloaded ? "arrow.down.circle.fill" : "arrow.down.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isDownloaded ? self.tokens.accent : self.secondaryInk)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(isDownloaded ? AppLanguage.text("已离线下载", en: "Downloaded") : AppLanguage.text("离线下载单集", en: "Download Episode"))
                    
                    Button {
                        self.podcastService.toggleSave(episode)
                    } label: {
                        Image(systemName: isSaved ? "heart.fill" : "heart")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(isSaved ? self.tokens.accent : self.secondaryInk)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    if let onOpenNote = self.onOpenNote {
                        Button {
                            let ts = PodcastTimeFormatter.string(for: displayedTime)
                            let md = "# \(episode.title)\n\n- 节目：\(episode.showName)\n- 时间戳：[\(ts)]\n- 链接：\(episode.sourceURL)\n\n"
                            onOpenNote("\(episode.title) · 听后笔记", md)
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(self.secondaryInk)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
            }
            
            if includeSleepAndVolume {
                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(self.mutedInk)
                        Slider(
                            value: Binding(
                                get: { self.podcastService.volume },
                                set: { self.podcastService.setVolume($0) }
                            ),
                            in: 0...1
                        )
                        .frame(width: 110)
                    }
                    
                    Menu {
                        Button(AppLanguage.text("关闭定时", en: "Off")) {
                            self.podcastService.setSleepTimer(minutes: nil)
                        }
                        Divider()
                        ForEach([15, 30, 45, 60], id: \.self) { mins in
                            Button(AppLanguage.text("\(mins) 分钟后暂停", en: "\(mins) min")) {
                                self.podcastService.setSleepTimer(minutes: mins)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "moon.zzz")
                                .font(.system(size: 11))
                            if let rem = self.podcastService.sleepTimerRemainingSec {
                                Text(PodcastTimeFormatter.string(for: TimeInterval(rem)))
                                    .monospacedDigit()
                            } else {
                                Text(AppLanguage.text("睡眠定时", en: "Sleep"))
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.podcastService.sleepTimerRemainingSec != nil ? self.tokens.accentText : self.secondaryInk)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(self.tokens.inset, in: Capsule())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
    }
    
    
    private func artworkTile(urlString: String?, size: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let urlStr = urlString, !urlStr.isEmpty, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            self.coverPlaceholder
                    }
                }
            } else {
                self.coverPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(self.tokens.hairlineStrong, lineWidth: 0.7))
        .shadow(color: Color.black.opacity(self.tokens.isDark ? 0.28 : 0.10), radius: 14, y: 6)
    }
    
    
    private func capsuleScrubBar(current: TimeInterval, duration: TimeInterval) -> some View {
        let ratio = min(1.0, max(0.0, current / max(duration, 1)))
        let isActive = self.isHoveringTrack || self.isScrubbing
        
        return GeometryReader { geo in
            let trackW = max(1, geo.size.width)
            let fillW = trackW * CGFloat(ratio)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(self.tokens.hairlineStrong)
                    .frame(height: isActive ? 6 : 4)
                
                Capsule()
                    .fill(self.tokens.accent)
                    .frame(width: max(isActive ? 6 : 4, fillW), height: isActive ? 6 : 4)
                
                if isActive {
                    Circle()
                        .fill(self.tokens.accent)
                        .frame(width: 11, height: 11)
                        .shadow(color: Color.black.opacity(0.22), radius: 2, y: 1)
                        .offset(x: min(max(0, fillW - 5.5), max(0, trackW - 11)))
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                    case .active(let loc):
                        self.isHoveringTrack = true
                        let f = min(max(0, loc.x / trackW), 1)
                        self.hoverTime = TimeInterval(f) * duration
                    case .ended:
                        self.isHoveringTrack = false
                        self.hoverTime = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let f = min(max(0, value.location.x / trackW), 1)
                        self.draftSeekTime = TimeInterval(f) * duration
                        self.isScrubbing = true
                    }
                    .onEnded { value in
                        let f = min(max(0, value.location.x / trackW), 1)
                        let target = TimeInterval(f) * duration
                        self.isScrubbing = false
                        self.podcastService.seek(to: target)
                    }
            )
        }
        .frame(height: 16)
        .animation(.easeOut(duration: 0.14), value: isActive)
    }
    
    
    private var coverPlaceholder: some View {
        ZStack {
            self.tokens.inset
            Image(systemName: "waveform")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(self.tokens.accent)
        }
    }
    
    
    // MARK: - Episode List Stage
    
    private var episodeListStage: some View {
        Group {
            if self.podcastService.isSearching || self.boardState.isAnalyzingIntent {
                VStack {
                    ProgressView()
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if self.displayedEpisodes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(self.mutedInk)
                    Text(self.filter == .downloaded
                         ? AppLanguage.text("暂无离线缓存单集，点击任意节目旁的下载按钮或让 Bot 帮你找", en: "No downloaded episodes yet")
                         : AppLanguage.text("暂无播客内容", en: "No episodes"))
                        .font(.system(size: 12))
                        .foregroundStyle(self.mutedInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 4) {
                        ForEach(self.displayedEpisodes) { episode in
                            self.episodeRow(episode)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
    
    
    private func episodeRow(_ episode: PodcastEpisodeItem) -> some View {
        let isCurrent = self.podcastService.currentEpisode?.id == episode.id
        let isPlaying = isCurrent && self.podcastService.phase.isPlaying
        let isSaved = self.podcastService.isSaved(episode.id)
        let isDownloaded = self.podcastService.isDownloaded(episode)
        let dlState = self.podcastService.downloadStates[episode.id]
        let isHovered = self.hoveredEpisodeID == episode.id
        
        return HStack(spacing: 12) {
            ZStack {
                if let url = URL(string: episode.artworkURL), !episode.artworkURL.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                self.rowArtworkFallback
                        }
                    }
                } else {
                    self.rowArtworkFallback
                }
                
                if isCurrent || isHovered {
                    Color.black.opacity(0.42)
                    Image(systemName: isPlaying ? "waveform" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            VStack(alignment: .leading, spacing: 3) {
                Text(episode.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(isCurrent ? self.tokens.accentText : self.tokens.primaryInk)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    if !episode.showName.isEmpty {
                        Text(episode.showName)
                            .lineLimit(1)
                    }
                    if episode.duration > 0 {
                        Text("· \(PodcastTimeFormatter.string(for: episode.duration))")
                            .monospacedDigit()
                    }
                    if isDownloaded {
                        Text("· \(AppLanguage.text("已缓存", en: "Offline"))")
                            .foregroundStyle(self.tokens.accentText)
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(self.secondaryInk)
            }
            
            Spacer(minLength: 8)
            
            Button {
                Task { _ = await self.podcastService.downloadEpisode(episode) }
            } label: {
                if case .downloading = dlState {
                    ProgressView().controlSize(.mini).frame(width: 24, height: 24)
                } else {
                    Image(systemName: isDownloaded ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(isDownloaded ? self.tokens.accent : self.mutedInk)
                        .frame(width: 26, height: 26)
                }
            }
            .buttonStyle(.plain)
            .opacity(isDownloaded || isHovered ? 1 : 0.45)
            .help(isDownloaded ? AppLanguage.text("已离线缓存", en: "Downloaded") : AppLanguage.text("下载到本地离线听", en: "Download Episode"))
            
            Button {
                self.podcastService.toggleSave(episode)
            } label: {
                Image(systemName: isSaved ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSaved ? self.tokens.accent : self.mutedInk)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .opacity(isSaved || isHovered ? 1 : 0.45)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isCurrent ? self.tokens.inset : (isHovered ? self.tokens.inset.opacity(0.6) : Color.clear),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            self.hoveredEpisodeID = hovering ? episode.id : (self.hoveredEpisodeID == episode.id ? nil : self.hoveredEpisodeID)
        }
        .onTapGesture {
            if isCurrent {
                self.podcastService.togglePlayback()
            } else {
                self.podcastService.loadAndPlay(episode: episode, autoplay: true)
            }
        }
        .pointerStyle(.link)
    }
    
    
    private var rowArtworkFallback: some View {
        ZStack {
            self.tokens.inset
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(self.mutedInk)
        }
    }
    
    
    // MARK: - Helpers & Bootstrap
    
    private func findEpisode(id: String) -> PodcastEpisodeItem? {
        if let match = self.podcastService.searchResults.first(where: { $0.id == id }) {
            return match
        }
        if let rec = self.podcastService.savedEpisodes.first(where: { $0.id == id })
            ?? self.podcastService.historyEpisodes.first(where: { $0.id == id })
        {
            return PodcastEpisodeItem(record: rec)
        }
        return nil
    }
    
    
    private static func plainTextSummary(from raw: String) -> String {
        raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    private func syncFromBoardState() {
        let q = self.boardState.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty && self.searchInput != q {
            self.searchInput = q
        }
        let queries = !self.boardState.topicChips.isEmpty
            ? self.boardState.topicChips
            : (q.isEmpty ? [] : [q])
        
        if queries.isEmpty {
            if self.podcastService.searchResults.isEmpty && self.podcastService.savedEpisodes.isEmpty {
                Task {
                    await self.podcastService.searchAndRecommend(for: [Self.starterChips[0]], autoplayFirst: false)
                }
            }
            return
        }
        
        Task {
            await self.podcastService.searchAndRecommend(for: queries, autoplayFirst: false)
        }
    }
}
