//
//  PaneBoardHostView.swift
//
//  CotEditor
//
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
import Defaults
import Observation
import SwiftUI

/// Observable wrapper allowing `EditorViewController` to push updated `PaneBoardState`
/// into an already-mounted `NSHostingController<PaneBoardHostView>` while also
/// accepting mutations from SwiftUI subviews.
@MainActor @Observable
final class PaneBoardControllerModel {
    
    var state: PaneBoardState {
        didSet {
            guard self.state != oldValue else { return }
            self.onStateChanged?(self.state)
        }
    }
    
    var onStateChanged: ((PaneBoardState) -> Void)?
    
    init(state: PaneBoardState) {
        self.state = state
    }
}


/// Hosts an interactive Market, Podcast, or NEWS board inside any editor pane tab,
/// harmonizing its surface directly with the active editor Theme and Studio Palette.
struct PaneBoardHostView: View {
    
    @Bindable var model: PaneBoardControllerModel
    var onRevertToDocument: () -> Void
    var onOpenNote: ((String, String) -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(.documentAppearance) private var documentAppearance
    @AppStorage(.theme) private var activeThemeName
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var mediaLibrary = UserMediaLibraryStore.shared
    @State private var isShowingBgPicker = false
    @State private var isBgButtonHovered = false
    
    private var resolvedIsDark: Bool {
        switch self.documentAppearance {
            case .light: false
            case .dark: true
            case .default: self.colorScheme == .dark
        }
    }
    
    private var tokens: StudioColorTokens {
        _ = self.studioPalette.revision
        return self.studioPalette.tokens(
            for: self.resolvedTheme,
            themeName: self.activeThemeName,
            isDark: self.resolvedBoardIsDark
        )
    }
    
    private var resolvedTheme: Theme? {
        (try? ThemeManager.shared.setting(name: self.activeThemeName))
            ?? self.studioPalette.synthesizedTheme(named: self.activeThemeName)
    }
    
    private var resolvedBoardIsDark: Bool {
        self.resolvedTheme?.isDarkTheme ?? self.resolvedIsDark
    }
    
    private var editorSurfaceColor: Color {
        if let theme = self.resolvedTheme {
            return Color(nsColor: theme.background.color)
        }
        return self.tokens.canvasTop
    }
    
    
    var body: some View {
        let _ = self.mediaLibrary.revision
        let activeTokens = self.tokens
        let surface = self.editorSurfaceColor
        let bgSlot = BoardBackgroundSlot(paneBoardKind: self.model.state.kind)
        let hasCustomBg = (self.mediaLibrary.boardAssignment(for: bgSlot) != nil
            && self.mediaLibrary.boardBackgroundImage(for: bgSlot) != nil)
        
        Group {
            switch self.model.state.kind {
                case .market:
                    MarketBoardView(
                        boardState: self.$model.state,
                        tokens: activeTokens,
                        surfaceColor: surface,
                        hasCustomBackground: hasCustomBg,
                        onRevertToDocument: self.onRevertToDocument,
                        onOpenNote: self.onOpenNote
                    )
                case .podcast:
                    PodcastBoardView(
                        boardState: self.$model.state,
                        tokens: activeTokens,
                        surfaceColor: surface,
                        hasCustomBackground: hasCustomBg,
                        onRevertToDocument: self.onRevertToDocument,
                        onOpenNote: self.onOpenNote
                    )
                case .news:
                    DashboardNewsCenterView(
                        newsService: AIHotNewsService.shared,
                        tokens: activeTokens,
                        surfaceColor: surface,
                        initialSelectedID: nil,
                        isEmbeddedInPane: true,
                        initialCategory: self.model.state.newsCategoryRaw.flatMap(NewsFeedCategory.init(rawValue:)),
                        initialSearchQuery: self.model.state.query,
                        hasCustomBackground: hasCustomBg,
                        onClose: self.onRevertToDocument,
                        onOpenExcerptDocument: self.onOpenNote
                    )
                case .butler:
                    ButlerCommandHubView(
                        hostWindow: nil,
                        isDockedPane: true,
                        initialSeedPrompt: self.model.state.query,
                        surfaceColor: surface,
                        isDarkOverride: self.resolvedBoardIsDark,
                        hasCustomBackground: hasCustomBg,
                        onDismiss: self.onRevertToDocument
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            BoardBackgroundBackdropView(
                slot: bgSlot,
                baseSurface: surface,
                isDark: self.resolvedBoardIsDark
            )
        }
        .overlay(alignment: .trailing) {
            Button {
                self.isShowingBgPicker.toggle()
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(self.resolvedBoardIsDark ? Color.white.opacity(0.88) : Color.black.opacity(0.76))
                    .frame(width: 26, height: 26)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(
                                (self.resolvedBoardIsDark ? Color.white : Color.black).opacity(0.14),
                                lineWidth: 0.75
                            )
                    )
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .opacity(self.isBgButtonHovered || self.isShowingBgPicker ? 1.0 : 0.48)
            .padding(.trailing, 8)
            .help(AppLanguage.text("设置当前看板背景", en: "Board Background"))
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.14)) {
                    self.isBgButtonHovered = hovering
                }
            }
            .popover(isPresented: self.$isShowingBgPicker, arrowEdge: .leading) {
                BackgroundLibraryPickerPopover(
                    title: AppLanguage.text("设置\(bgSlot.title)背景", en: "\(bgSlot.title) Background"),
                    slot: bgSlot,
                    onSelect: { asset in
                        self.mediaLibrary.setBoardBackground(assetID: asset.id, for: bgSlot)
                    }
                )
            }
        }
    }
}
