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
    case history
    
    var id: String { self.rawValue }
    
    var label: String {
        switch self {
            case .discover: AppLanguage.text("探索", en: "Discover")
            case .saved: AppLanguage.text("收藏", en: "Saved")
            case .history: AppLanguage.text("历史", en: "History")
        }
    }
}


/// Embedded Podcast Search, Link Importer & PodPin-Inspired Listening Stage fused natively into CotEditor panes.
struct PodcastBoardView: View {
    
    @Binding var boardState: PaneBoardState
    let tokens: StudioColorTokens
    var surfaceColor: Color? = nil
    var onRevertToDocument: (() -> Void)? = nil
    var onOpenNote: ((String, String) -> Void)?
    
    @State private var podcastService = CotPodcastService.shared
    @State private var artworkColor = PodcastArtworkColorModel()
    @State private var filter: PodcastBoardFilter = .discover
    @State private var searchInput: String = ""
    @State private var isScrubbing = false
    @State private var isHoveringTrack = false
    @State private var draftSeekTime: TimeInterval = 0
    @State private var hoverTime: TimeInterval?
    @State private var hoveredEpisodeID: String?
    
    private static let starterChips = ["心理与自我", "商业思考", "科技人文", "松弛漫谈"]
    
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
            case .history:
                return self.podcastService.historyEpisodes.map(PodcastEpisodeItem.init(record:))
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
                .frame(height: 1)
            
            GeometryReader { geo in
                let hasPlayer = (self.podcastService.currentEpisode != nil)
                let isWide = geo.size.width >= 640
                
                if hasPlayer && isWide {
                    HStack(spacing: 0) {
                        self.playerStage
                            .frame(width: min(350, max(270, geo.size.width * 0.40)))
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Rectangle()
                            .fill(self.tokens.hairline)
                            .frame(width: 1)
                        self.episodeListStage
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if hasPlayer {
                    VStack(spacing: 0) {
                        self.playerStage
                            .frame(height: min(290, max(220, geo.size.height * 0.46)))
                            .transition(.move(edge: .top).combined(with: .opacity))
                        Rectangle()
                            .fill(self.tokens.hairline)
                            .frame(height: 1)
                        self.episodeListStage
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    self.episodeListStage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24), value: self.podcastService.currentEpisode?.id)
        }
        .background(self.canvasBackground)
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
    
    
    // MARK: - Top Control Bar
    
    private var topControlBar: some View {
        HStack(spacing: 10) {
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
            .frame(maxWidth: 280)
            
            Spacer(minLength: 4)
            
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
    
    
    // MARK: - PodPin-Inspired Listening Stage (Only Shown When Episode Active)
    
    private var playerStage: some View {
        let episode = self.podcastService.currentEpisode
        let duration = max(self.podcastService.duration, episode?.duration ?? 0, 1)
        let displayedTime = self.isScrubbing ? self.draftSeekTime : self.podcastService.currentTime
        let isSaved = episode.map { self.podcastService.isSaved($0.id) } ?? false
        
        return ZStack {
            if let ambient = self.artworkColor.color {
                ambient.opacity(self.tokens.isDark ? 0.18 : 0.08)
            } else {
                Color.primary.opacity(self.tokens.isDark ? 0.03 : 0.015)
            }
            
            VStack(spacing: 14) {
                Spacer(minLength: 6)
                
                Group {
                    if let urlStr = episode?.artworkURL, let url = URL(string: urlStr) {
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
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(self.tokens.hairlineStrong, lineWidth: 0.7))
                .shadow(color: Color.black.opacity(self.tokens.isDark ? 0.28 : 0.10), radius: 14, y: 6)
                
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
                
                // Custom Tactile Capsule Scrub Track
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
                
                HStack(spacing: 16) {
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
                                .frame(width: 42, height: 42)
                            if self.podcastService.phase == .loading || self.podcastService.phase == .buffering {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(self.tokens.onAccentInk)
                            } else {
                                Image(systemName: self.podcastService.phase.hasPlaybackIntent ? "pause.fill" : "play.fill")
                                    .font(.system(size: 15, weight: .semibold))
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
                
                Spacer(minLength: 6)
            }
        }
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
                }
                .font(.system(size: 11.5))
                .foregroundStyle(self.secondaryInk)
            }
            
            Spacer(minLength: 8)
            
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
    
    
    // MARK: - Bootstrap
    
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
