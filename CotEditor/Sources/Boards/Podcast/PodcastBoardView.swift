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
    
    var id: String { self.rawValue }
    
    var label: String {
        switch self {
            case .discover: AppLanguage.text("发现", en: "Discover")
            case .saved: AppLanguage.text("收藏", en: "Saved")
            case .downloaded: AppLanguage.text("离线", en: "Offline")
        }
    }
}


/// Calm, single-layout embedded Podcast player & episode list.
/// Zero mode jumping, zero icon clutter — clean typography and steady bottom playback bar.
struct PodcastBoardView: View {
    
    @Binding var boardState: PaneBoardState
    let tokens: StudioColorTokens
    var surfaceColor: Color? = nil
    var hasCustomBackground: Bool = false
    var onRevertToDocument: (() -> Void)? = nil
    var onOpenNote: ((String, String) -> Void)?
    
    @State private var podcastService = CotPodcastService.shared
    @State private var filter: PodcastBoardFilter = .discover
    @State private var searchInput: String = ""
    @State private var isScrubbing = false
    @State private var draftSeekTime: TimeInterval = 0
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
        }
    }
    
    private var effectiveChips: [String] {
        self.boardState.topicChips.isEmpty ? Self.starterChips : self.boardState.topicChips
    }
    
    
    var body: some View {
        VStack(spacing: 0) {
            self.topControlBar
            
            Rectangle()
                .fill(self.tokens.hairline)
                .frame(height: 0.75)
            
            if self.filter == .discover {
                self.topicChipStrip
                Rectangle()
                    .fill(self.tokens.hairline.opacity(0.6))
                    .frame(height: 0.5)
            }
            
            self.episodeListStage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            if let current = self.podcastService.currentEpisode {
                Rectangle()
                    .fill(self.tokens.hairline)
                    .frame(height: 0.75)
                self.bottomPlayerBar(episode: current)
            }
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
    }
    
    
    // MARK: - Minimal Top Bar
    
    private var topControlBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(self.mutedInk)
                TextField(AppLanguage.text("搜索播客或粘贴链接", en: "Search podcasts"), text: self.$searchInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(self.tokens.primaryInk)
                    .onSubmit {
                        self.submitSearch()
                    }
                if !self.searchInput.isEmpty {
                    Button {
                        self.searchInput = ""
                    } label: {
                        Text("×")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(self.mutedInk)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: 300)
            .frame(height: 26)
            .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            
            Spacer(minLength: 8)
            
            HStack(spacing: 1) {
                ForEach(PodcastBoardFilter.allCases) { tab in
                    let active = (self.filter == tab)
                    Button {
                        self.filter = tab
                    } label: {
                        Text(tab.label)
                            .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? self.tokens.primaryInk : self.secondaryInk)
                            .padding(.horizontal, 9)
                            .frame(height: 22)
                            .background(active ? self.tokens.card : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(2)
            .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
            
            if let onRevertToDocument = self.onRevertToDocument {
                Button(action: onRevertToDocument) {
                    Text(AppLanguage.text("文档", en: "Doc"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.secondaryInk)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(AppLanguage.text("切回文档编辑", en: "Back to Document"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }
    
    
    private var topicChipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
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
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? self.tokens.primaryInk : self.secondaryInk)
                            .padding(.horizontal, 9)
                            .frame(height: 22)
                            .background(
                                selected ? self.tokens.inset : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(selected ? self.tokens.hairlineStrong : self.tokens.hairline, lineWidth: 0.6)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }
    
    
    // MARK: - Clean Typographic Episode List
    
    private var episodeListStage: some View {
        Group {
            if self.podcastService.isSearching || self.boardState.isAnalyzingIntent {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if self.displayedEpisodes.isEmpty {
                Text(self.filter == .downloaded
                     ? AppLanguage.text("暂无离线单集", en: "No offline episodes")
                     : AppLanguage.text("暂无播客内容", en: "No episodes"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(self.mutedInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 2) {
                        ForEach(self.displayedEpisodes) { episode in
                            self.episodeRow(episode)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 780, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }
    
    
    private func episodeRow(_ episode: PodcastEpisodeItem) -> some View {
        let isCurrent = self.podcastService.currentEpisode?.id == episode.id
        let isPlaying = isCurrent && self.podcastService.phase.isPlaying
        let isSaved = self.podcastService.isSaved(episode.id)
        let isDownloaded = self.podcastService.isDownloaded(episode)
        let isHovered = self.hoveredEpisodeID == episode.id
        
        return HStack(spacing: 12) {
            self.artworkTile(urlString: episode.artworkURL, size: 38, cornerRadius: 7)
            
            VStack(alignment: .leading, spacing: 2.5) {
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
                        Text("· \(AppLanguage.text("已离线", en: "Offline"))")
                            .foregroundStyle(self.tokens.accentText)
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(self.secondaryInk)
            }
            
            Spacer(minLength: 10)
            
            if isCurrent {
                Text(isPlaying ? AppLanguage.text("播放中", en: "Playing") : AppLanguage.text("已暂停", en: "Paused"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(self.tokens.accentText)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(self.tokens.positivePillBg, in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
            } else if isSaved && !isHovered {
                Text(AppLanguage.text("已收藏", en: "Saved"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(self.mutedInk)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isCurrent ? self.tokens.inset : (isHovered ? self.tokens.inset.opacity(0.55) : Color.clear),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .contextMenu {
            Button(isSaved ? AppLanguage.text("取消收藏", en: "Unsave") : AppLanguage.text("收藏单集", en: "Save")) {
                self.podcastService.toggleSave(episode)
            }
            Button(isDownloaded ? AppLanguage.text("已离线缓存", en: "Downloaded") : AppLanguage.text("离线下载", en: "Download")) {
                Task { _ = await self.podcastService.downloadEpisode(episode) }
            }
            .disabled(isDownloaded)
            if let onOpenNote = self.onOpenNote {
                Divider()
                Button(AppLanguage.text("记听后笔记", en: "Open Note")) {
                    let md = "# \(episode.title)\n\n- 节目：\(episode.showName)\n- 链接：\(episode.sourceURL)\n\n"
                    onOpenNote("\(episode.title) · 听后笔记", md)
                }
            }
        }
    }
    
    
    // MARK: - Steady Docked Bottom Player Bar
    
    private func bottomPlayerBar(episode: PodcastEpisodeItem) -> some View {
        let duration = max(self.podcastService.duration, episode.duration, 1)
        let displayedTime = self.isScrubbing ? self.draftSeekTime : self.podcastService.currentTime
        let isSaved = self.podcastService.isSaved(episode.id)
        
        return VStack(spacing: 0) {
            self.thinScrubBar(current: displayedTime, duration: duration)
            
            HStack(spacing: 12) {
                self.artworkTile(urlString: episode.artworkURL, size: 36, cornerRadius: 6)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if !episode.showName.isEmpty {
                            Text(episode.showName).lineLimit(1)
                        }
                        Text("· \(PodcastTimeFormatter.string(for: displayedTime)) / \(PodcastTimeFormatter.string(for: duration))")
                            .monospacedDigit()
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(self.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 10) {
                    Button {
                        self.podcastService.skipBackward()
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(self.secondaryInk)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    Button {
                        self.podcastService.togglePlayback()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(self.tokens.accent)
                                .frame(width: 30, height: 30)
                            if self.podcastService.phase == .loading || self.podcastService.phase == .buffering {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(self.tokens.onAccentInk)
                            } else {
                                Image(systemName: self.podcastService.phase.hasPlaybackIntent ? "pause.fill" : "play.fill")
                                    .font(.system(size: 12, weight: .semibold))
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
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(self.secondaryInk)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                
                Menu {
                    ForEach(CotPodcastService.supportedRates, id: \.self) { r in
                        Button("\(r.formatted(.number.precision(.fractionLength(0...2))))×") {
                            self.podcastService.setRate(r)
                        }
                    }
                } label: {
                    Text("\(self.podcastService.rate.formatted(.number.precision(.fractionLength(0...2))))×")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(self.secondaryInk)
                        .padding(.horizontal, 6)
                        .frame(height: 22)
                        .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                
                Button {
                    self.podcastService.toggleSave(episode)
                } label: {
                    Text(isSaved ? AppLanguage.text("已收藏", en: "Saved") : AppLanguage.text("收藏", en: "Save"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSaved ? self.tokens.accentText : self.secondaryInk)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                if let onOpenNote = self.onOpenNote {
                    Button {
                        let ts = PodcastTimeFormatter.string(for: displayedTime)
                        let md = "# \(episode.title)\n\n- 节目：\(episode.showName)\n- 时间戳：[\(ts)]\n- 链接：\(episode.sourceURL)\n\n"
                        onOpenNote("\(episode.title) · 听后笔记", md)
                    } label: {
                        Text(AppLanguage.text("笔记", en: "Note"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(self.secondaryInk)
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
        }
        .background(self.tokens.card.opacity(self.hasCustomBackground ? 0.72 : 0.92))
    }
    
    
    private func thinScrubBar(current: TimeInterval, duration: TimeInterval) -> some View {
        let ratio = min(1.0, max(0.0, current / max(duration, 1)))
        return GeometryReader { geo in
            let width = max(1, geo.size.width)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(self.tokens.hairline)
                    .frame(height: 3)
                Rectangle()
                    .fill(self.tokens.accent)
                    .frame(width: width * CGFloat(ratio), height: 3)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let f = min(max(0, value.location.x / width), 1)
                        self.draftSeekTime = TimeInterval(f) * duration
                        self.isScrubbing = true
                    }
                    .onEnded { value in
                        let f = min(max(0, value.location.x / width), 1)
                        self.isScrubbing = false
                        self.podcastService.seek(to: TimeInterval(f) * duration)
                    }
            )
        }
        .frame(height: 8)
    }
    
    
    private func artworkTile(urlString: String?, size: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let urlStr = urlString, !urlStr.isEmpty, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            self.tokens.inset
                    }
                }
            } else {
                self.tokens.inset
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(self.tokens.hairline, lineWidth: 0.6)
        )
    }
    
    
    // MARK: - Actions & Bootstrap
    
    private func submitSearch() {
        let q = self.searchInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        self.filter = .discover
        self.boardState.query = q
        self.boardState.dynamicTitle = q.hasPrefix("http") ? nil : q
        Task {
            await self.podcastService.searchAndRecommend(for: [q], autoplayFirst: true)
        }
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
