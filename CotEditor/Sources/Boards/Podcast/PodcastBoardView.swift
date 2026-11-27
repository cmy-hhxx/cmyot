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


/// Apple-style tactile press feedback (press-only compression, zero hover twitch).
private struct AppleTactileButtonStyle: ButtonStyle {
    
    var pressedScale: CGFloat = 0.94
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? self.pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}


/// Smooth Apple Music / Apple Podcasts 3-bar fluid equalizer overlay for the playing episode.
private struct PodcastAudioBarsIndicator: View {
    
    let isPlaying: Bool
    var color: Color = .white
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !self.isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    let height = self.barHeight(for: index, at: t)
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(self.color)
                        .frame(width: 2.5, height: height)
                }
            }
            .frame(width: 14, height: 13, alignment: .bottom)
        }
    }
    
    
    private func barHeight(for index: Int, at time: TimeInterval) -> CGFloat {
        guard self.isPlaying else {
            return index == 1 ? 5.5 : 3.5
        }
        let speed = 5.4 + Double(index) * 1.15
        let phase = Double(index) * 1.7
        let wave = 0.5 + 0.5 * sin(time * speed + phase)
        return CGFloat(3.5 + wave * 9.5)
    }
}


/// Interactive Apple Podcasts-style scrub bar with buffered track, hover expansion, and floating time preview.
private struct PodcastScrubBar: View {
    
    let currentTime: TimeInterval
    let duration: TimeInterval
    let bufferedProgress: Double
    let isPlaying: Bool
    let tokens: StudioColorTokens
    let accentColor: Color
    let onScrubChanged: (TimeInterval) -> Void
    let onScrubEnded: (TimeInterval) -> Void
    
    @State private var isHovered = false
    @State private var isDragging = false
    @State private var dragRatio: Double = 0
    
    private var displayedRatio: Double {
        if self.isDragging { return self.dragRatio }
        return min(1.0, max(0.0, self.currentTime / max(self.duration, 1)))
    }
    
    private var isExpanded: Bool { self.isHovered || self.isDragging }
    
    
    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let fillW = width * CGFloat(self.displayedRatio)
            let bufW = width * CGFloat(min(1.0, max(0.0, self.bufferedProgress)))
            let trackH: CGFloat = self.isExpanded ? 5.0 : 3.0
            
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(self.tokens.hairline)
                    .frame(height: trackH)
                
                if bufW > 0 {
                    Capsule()
                        .fill(self.tokens.hairlineStrong.opacity(0.65))
                        .frame(width: bufW, height: trackH)
                        .animation(.easeOut(duration: 0.25), value: self.bufferedProgress)
                }
                
                Capsule()
                    .fill(self.accentColor)
                    .frame(width: fillW, height: trackH)
                    .animation(self.isDragging ? nil : .linear(duration: self.isPlaying ? 0.11 : 0.18), value: self.displayedRatio)
                
                Circle()
                    .fill(self.accentColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
                    .position(x: min(max(5, fillW), width - 5), y: geo.size.height / 2)
                    .opacity(self.isExpanded ? 1 : 0)
                    .animation(.easeOut(duration: 0.14), value: self.isExpanded)
                
                if self.isDragging {
                    let previewSec = self.dragRatio * max(self.duration, 1)
                    Text(PodcastTimeFormatter.string(for: previewSec))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(self.tokens.primaryInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(self.tokens.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(self.tokens.hairlineStrong, lineWidth: 0.6))
                        .shadow(color: Color.black.opacity(0.12), radius: 5, y: 2)
                        .position(x: min(max(28, fillW), width - 28), y: -12)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: self.isExpanded)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                self.isHovered = hovering
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = min(max(0, Double(value.location.x / width)), 1)
                        self.dragRatio = ratio
                        self.isDragging = true
                        self.onScrubChanged(ratio * max(self.duration, 1))
                    }
                    .onEnded { value in
                        let ratio = min(max(0, Double(value.location.x / width)), 1)
                        self.dragRatio = ratio
                        self.isDragging = false
                        self.onScrubEnded(ratio * max(self.duration, 1))
                    }
            )
            .pointerStyle(.link)
        }
        .frame(height: 12)
    }
}


/// Calm, Apple Podcasts-inspired embedded player & episode list with spring transitions and 10Hz scrubbing.
struct PodcastBoardView: View {
    
    @Binding var boardState: PaneBoardState
    let tokens: StudioColorTokens
    var surfaceColor: Color? = nil
    var hasCustomBackground: Bool = false
    var onRevertToDocument: (() -> Void)? = nil
    var onOpenNote: ((String, String) -> Void)?
    
    @State private var podcastService = CotPodcastService.shared
    @State private var artworkTint = PodcastArtworkColorModel()
    @State private var filter: PodcastBoardFilter = .discover
    @State private var searchInput: String = ""
    @State private var isScrubbing = false
    @State private var draftSeekTime: TimeInterval = 0
    @State private var hoveredEpisodeID: String?
    @State private var previousNonZeroVolume: Double = 0.85
    @Namespace private var filterPillNamespace
    
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
    
    private var savedProgressByID: [String: Double] {
        var map: [String: Double] = [:]
        for record in self.podcastService.historyEpisodes where record.durationSec > 0 && record.playbackPositionSec > 5 {
            map[record.id] = min(1.0, max(0.0, record.playbackPositionSec / record.durationSec))
        }
        return map
    }
    
    
    var body: some View {
        VStack(spacing: 0) {
            self.topControlBar
            
            Rectangle()
                .fill(self.tokens.hairline)
                .frame(height: 0.75)
            
            if self.filter == .discover {
                self.topicChipStrip
                    .transition(.opacity)
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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: self.podcastService.currentEpisode?.id)
        .animation(.easeOut(duration: 0.2), value: self.filter)
        .background(self.hasCustomBackground ? Color.clear : self.canvasBackground)
        .onAppear {
            self.syncFromBoardState()
            self.artworkTint.load(from: self.podcastService.currentEpisode?.artworkURL)
        }
        .onChange(of: self.podcastService.currentEpisode?.artworkURL) { _, nextURL in
            self.artworkTint.load(from: nextURL)
        }
        .onChange(of: self.boardState.query) { _, _ in
            self.syncFromBoardState()
        }
        .onChange(of: self.boardState.topicChips) { _, _ in
            self.syncFromBoardState()
        }
    }
    
    
    // MARK: - Minimal Top Bar with Sliding Segmented Pill
    
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
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(self.mutedInk)
                    }
                    .buttonStyle(AppleTactileButtonStyle())
                }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: 300)
            .frame(height: 26)
            .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
            
            Spacer(minLength: 8)
            
            HStack(spacing: 1) {
                ForEach(PodcastBoardFilter.allCases) { tab in
                    let active = (self.filter == tab)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                            self.filter = tab
                        }
                    } label: {
                        Text(tab.label)
                            .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? self.tokens.primaryInk : self.secondaryInk)
                            .padding(.horizontal, 10)
                            .frame(height: 22)
                            .background {
                                if active {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(self.tokens.card)
                                        .shadow(color: Color.black.opacity(self.tokens.isDark ? 0.22 : 0.06), radius: 2, y: 0.5)
                                        .matchedGeometryEffect(id: "podcastFilterPill", in: self.filterPillNamespace)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(2)
            .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            
            if let onRevertToDocument = self.onRevertToDocument {
                Button(action: onRevertToDocument) {
                    Text(AppLanguage.text("文档", en: "Doc"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.secondaryInk)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                }
                .buttonStyle(AppleTactileButtonStyle())
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
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            self.filter = .discover
                            self.searchInput = chip
                            self.boardState.query = chip
                        }
                        Task {
                            await self.podcastService.searchAndRecommend(for: [chip], autoplayFirst: false)
                        }
                    } label: {
                        Text(chip)
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? self.tokens.primaryInk : self.secondaryInk)
                            .padding(.horizontal, 9.5)
                            .frame(height: 22)
                            .background(
                                selected ? self.tokens.inset : Color.clear,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(selected ? self.tokens.hairlineStrong : self.tokens.hairline, lineWidth: 0.6)
                            )
                    }
                    .buttonStyle(AppleTactileButtonStyle(pressedScale: 0.96))
                    .pointerStyle(.link)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }
    
    
    // MARK: - Clean Typographic Episode List
    
    private var episodeListStage: some View {
        let progressMap = self.savedProgressByID
        return Group {
            if self.podcastService.isSearching || self.boardState.isAnalyzingIntent {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else if self.displayedEpisodes.isEmpty {
                Text(self.filter == .downloaded
                     ? AppLanguage.text("暂无离线单集", en: "No offline episodes")
                     : AppLanguage.text("暂无播客内容", en: "No episodes"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(self.mutedInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 2) {
                        ForEach(self.displayedEpisodes) { episode in
                            self.episodeRow(episode, savedProgress: progressMap[episode.id])
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 780, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: self.podcastService.isSearching)
    }
    
    
    private func episodeRow(_ episode: PodcastEpisodeItem, savedProgress: Double?) -> some View {
        let isCurrent = self.podcastService.currentEpisode?.id == episode.id
        let isPlaying = isCurrent && self.podcastService.phase.isPlaying
        let isBuffering = isCurrent && (self.podcastService.phase == .loading || self.podcastService.phase == .buffering)
        let isSaved = self.podcastService.isSaved(episode.id)
        let isDownloaded = self.podcastService.isDownloaded(episode)
        let isHovered = self.hoveredEpisodeID == episode.id
        
        return HStack(spacing: 12) {
            ZStack {
                self.artworkTile(urlString: episode.artworkURL, size: 40, cornerRadius: 7.5)
                
                if isCurrent {
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(Color.black.opacity(0.36))
                    if isBuffering {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white)
                    } else {
                        PodcastAudioBarsIndicator(isPlaying: isPlaying, color: .white)
                    }
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 40, height: 40)
            .animation(.easeOut(duration: 0.16), value: isHovered)
            .animation(.easeOut(duration: 0.18), value: isCurrent)
            
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
                        Text("· \(AppLanguage.text("已离线", en: "Offline"))")
                            .foregroundStyle(self.tokens.accentText)
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(self.secondaryInk)
                
                if let progress = savedProgress, !isCurrent, progress > 0.02, progress < 0.98 {
                    GeometryReader { barGeo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(self.tokens.hairline)
                            Capsule()
                                .fill(self.tokens.accent.opacity(0.72))
                                .frame(width: barGeo.size.width * CGFloat(progress))
                        }
                    }
                    .frame(width: 72, height: 2.5)
                    .padding(.top, 1)
                }
            }
            
            Spacer(minLength: 10)
            
            if isCurrent {
                Text(isPlaying ? AppLanguage.text("播放中", en: "Playing") : (isBuffering ? AppLanguage.text("缓冲中", en: "Loading") : AppLanguage.text("已暂停", en: "Paused")))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(self.tokens.accentText)
                    .padding(.horizontal, 7.5)
                    .frame(height: 20)
                    .background(self.tokens.positivePillBg, in: Capsule())
                    .transition(.opacity)
            } else if isSaved && !isHovered {
                Text(AppLanguage.text("已收藏", en: "Saved"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(self.mutedInk)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7.5)
        .background(
            isCurrent ? self.tokens.inset : (isHovered ? self.tokens.inset.opacity(0.55) : Color.clear),
            in: RoundedRectangle(cornerRadius: 8.5, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .strokeBorder(isCurrent ? self.tokens.hairlineStrong : Color.clear, lineWidth: 0.6)
        )
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: isCurrent)
        .contentShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))
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
    
    
    // MARK: - Apple-Native Docked Bottom Player Bar
    
    private func bottomPlayerBar(episode: PodcastEpisodeItem) -> some View {
        let duration = max(self.podcastService.duration, episode.duration, 1)
        let displayedTime = self.isScrubbing ? self.draftSeekTime : self.podcastService.currentTime
        let isSaved = self.podcastService.isSaved(episode.id)
        let isBuffering = self.podcastService.phase == .loading || self.podcastService.phase == .buffering
        let ambientColor = self.artworkTint.color
        
        return VStack(spacing: 0) {
            PodcastScrubBar(
                currentTime: displayedTime,
                duration: duration,
                bufferedProgress: self.podcastService.bufferedProgress,
                isPlaying: self.podcastService.phase.isPlaying,
                tokens: self.tokens,
                accentColor: self.tokens.accent,
                onScrubChanged: { target in
                    self.draftSeekTime = target
                    self.isScrubbing = true
                },
                onScrubEnded: { target in
                    self.isScrubbing = false
                    self.podcastService.seek(to: target)
                }
            )
            .padding(.horizontal, 14)
            .padding(.top, 4)
            
            HStack(spacing: 12) {
                self.artworkTile(urlString: episode.artworkURL, size: 38, cornerRadius: 7)
                    .id(episode.id)
                    .transition(.opacity)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(self.tokens.primaryInk)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if !episode.showName.isEmpty {
                            Text(episode.showName).lineLimit(1)
                        }
                        Text("· \(PodcastTimeFormatter.string(for: displayedTime))")
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(PodcastTimeFormatter.remainingString(current: displayedTime, duration: duration))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(self.mutedInk)
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(self.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                self.transportControls(isBuffering: isBuffering)
                
                self.compactVolumeControl
                
                self.playerAccessoryControls(episode: episode, isSaved: isSaved, displayedTime: displayedTime)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
        }
        .background {
            ZStack {
                self.tokens.card.opacity(self.hasCustomBackground ? 0.76 : 0.94)
                if let ambientColor {
                    ambientColor
                        .opacity(self.tokens.isDark ? 0.14 : 0.06)
                        .animation(.easeInOut(duration: 0.45), value: ambientColor)
                }
            }
        }
    }
    
    
    private func transportControls(isBuffering: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                self.podcastService.skipBackward()
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(self.secondaryInk)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(AppleTactileButtonStyle(pressedScale: 0.88))
            .pointerStyle(.link)
            
            Button {
                self.podcastService.togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(self.tokens.accent)
                        .frame(width: 32, height: 32)
                        .shadow(color: Color.black.opacity(self.tokens.isDark ? 0.26 : 0.10), radius: 4, y: 1.5)
                    if isBuffering {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(self.tokens.onAccentInk)
                            .transition(.opacity)
                    } else {
                        Image(systemName: self.podcastService.phase.hasPlaybackIntent ? "pause.fill" : "play.fill")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(self.tokens.onAccentInk)
                            .offset(x: self.podcastService.phase.hasPlaybackIntent ? 0 : 0.8)
                            .contentTransition(.symbolEffect(.replace.downUp))
                    }
                }
            }
            .buttonStyle(AppleTactileButtonStyle(pressedScale: 0.90))
            .pointerStyle(.link)
            
            Button {
                self.podcastService.skipForward()
            } label: {
                Image(systemName: "goforward.30")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(self.secondaryInk)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(AppleTactileButtonStyle(pressedScale: 0.88))
            .pointerStyle(.link)
        }
    }
    
    
    private var compactVolumeControl: some View {
        let vol = self.podcastService.volume
        let iconName: String = if vol <= 0.01 {
            "speaker.slash.fill"
        } else if vol < 0.45 {
            "speaker.wave.1.fill"
        } else {
            "speaker.wave.2.fill"
        }
        return HStack(spacing: 5) {
            Button {
                if vol > 0.01 {
                    self.previousNonZeroVolume = vol
                    self.podcastService.setVolume(0)
                } else {
                    self.podcastService.setVolume(max(0.25, self.previousNonZeroVolume))
                }
            } label: {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(self.secondaryInk)
                    .frame(width: 18, height: 20)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(AppleTactileButtonStyle())
            .pointerStyle(.link)
            
            GeometryReader { geo in
                let w = max(1, geo.size.width)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(self.tokens.hairline)
                        .frame(height: 3)
                    Capsule()
                        .fill(self.secondaryInk.opacity(0.8))
                        .frame(width: w * CGFloat(vol), height: 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            self.podcastService.setVolume(Double(value.location.x / w))
                        }
                )
            }
            .frame(width: 48, height: 16)
            .pointerStyle(.link)
        }
    }
    
    
    private func playerAccessoryControls(episode: PodcastEpisodeItem, isSaved: Bool, displayedTime: TimeInterval) -> some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(CotPodcastService.supportedRates, id: \.self) { r in
                    Button("\(r.formatted(.number.precision(.fractionLength(0...2))))×") {
                        self.podcastService.setRate(r)
                    }
                }
            } label: {
                Text("\(self.podcastService.rate.formatted(.number.precision(.fractionLength(0...2))))×")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(self.secondaryInk)
                    .padding(.horizontal, 6.5)
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
            .buttonStyle(AppleTactileButtonStyle())
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
                .buttonStyle(AppleTactileButtonStyle())
                .pointerStyle(.link)
            }
        }
    }
    
    
    private func artworkTile(urlString: String?, size: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let urlStr = urlString, !urlStr.isEmpty, let url = URL(string: urlStr) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.22))) { phase in
                    switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                                .transition(.opacity)
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
            self.filter = .discover
        }
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
