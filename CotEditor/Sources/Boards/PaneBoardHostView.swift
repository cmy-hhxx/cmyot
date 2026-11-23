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
    
    private var resolvedIsDark: Bool {
        switch self.documentAppearance {
            case .light: false
            case .dark: true
            case .default: self.colorScheme == .dark
        }
    }
    
    private var tokens: StudioColorTokens {
        _ = self.studioPalette.revision
        return self.studioPalette.tokens(isDark: self.resolvedIsDark)
    }
    
    private var editorSurfaceColor: Color {
        if let theme = (try? ThemeManager.shared.setting(name: self.activeThemeName))
            ?? self.studioPalette.synthesizedTheme(named: self.activeThemeName)
        {
            return Color(nsColor: theme.background.color)
        }
        return self.tokens.canvasTop
    }
    
    
    var body: some View {
        let activeTokens = self.tokens
        let surface = self.editorSurfaceColor
        Group {
            switch self.model.state.kind {
                case .market:
                    MarketBoardView(
                        boardState: self.$model.state,
                        tokens: activeTokens,
                        surfaceColor: surface,
                        onRevertToDocument: self.onRevertToDocument,
                        onOpenNote: self.onOpenNote
                    )
                case .podcast:
                    PodcastBoardView(
                        boardState: self.$model.state,
                        tokens: activeTokens,
                        surfaceColor: surface,
                        onRevertToDocument: self.onRevertToDocument,
                        onOpenNote: self.onOpenNote
                    )
                case .news:
                    DashboardNewsCenterView(
                        newsService: AIHotNewsService.shared,
                        tokens: activeTokens,
                        initialSelectedID: nil,
                        isEmbeddedInPane: true,
                        initialCategory: self.model.state.newsCategoryRaw.flatMap(NewsFeedCategory.init(rawValue:)),
                        initialSearchQuery: self.model.state.query,
                        onClose: self.onRevertToDocument,
                        onOpenExcerptDocument: self.onOpenNote
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(surface)
    }
}
