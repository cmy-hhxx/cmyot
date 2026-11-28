//
//  SidebarAppearanceContainerPane.swift
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

enum AppearanceSubTab: String, CaseIterable, Identifiable, Sendable {
    
    case theme
    case wallpaper
    case appIcon
    case mediaLibrary
    case motion
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
            case .theme: AppLanguage.text("配色", en: "Theme")
            case .wallpaper: AppLanguage.text("壁纸", en: "Wallpaper")
            case .appIcon: AppLanguage.text("图标", en: "App Icon")
            case .mediaLibrary: AppLanguage.text("素材库", en: "Library")
            case .motion: AppLanguage.text("动效", en: "Motion")
        }
    }
}


/// Unified Appearance pane hosting Theme, Wallpaper, App Icon, Media Library, and Motion sub-tabs.
struct SidebarAppearanceContainerPane: View {
    
    var settingsState: SidebarSettingsState? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSubTab: AppearanceSubTab = .theme
    @Namespace private var subTabNamespace
    
    
    var body: some View {
        VStack(spacing: 0) {
            self.subTabBar
            
            Rectangle()
                .fill(self.colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                .frame(height: 0.5)
            
            Group {
                switch self.selectedSubTab {
                    case .theme:
                        ScrollView {
                            SidebarAppearanceThemePane()
                                .padding(.horizontal, SettingsDesignTokens.contentPadding)
                                .padding(.top, 16)
                                .padding(.bottom, 28)
                                .frame(width: SettingsDesignTokens.detailWidth, alignment: .topLeading)
                        }
                        .frame(width: SettingsDesignTokens.detailWidth)
                        .frame(maxHeight: .infinity)
                        
                    case .wallpaper:
                        SidebarWallpaperSettingsPane()
                            .frame(width: SettingsDesignTokens.detailWidth)
                            .frame(maxHeight: .infinity)
                        
                    case .appIcon:
                        SidebarAppIconSettingsPane()
                            .frame(width: SettingsDesignTokens.detailWidth)
                            .frame(maxHeight: .infinity)
                        
                    case .mediaLibrary:
                        MediaLibrarySettingsView()
                            .frame(width: SettingsDesignTokens.detailWidth)
                            .frame(maxHeight: .infinity)
                        
                    case .motion:
                        ScrollView {
                            SidebarEffectsSettingsPane()
                                .padding(.horizontal, SettingsDesignTokens.contentPadding)
                                .padding(.top, 16)
                                .padding(.bottom, 28)
                                .frame(width: SettingsDesignTokens.detailWidth, alignment: .topLeading)
                        }
                        .frame(width: SettingsDesignTokens.detailWidth)
                        .frame(maxHeight: .infinity)
                }
            }
            .id(self.selectedSubTab)
            .transition(.opacity)
        }
        .frame(width: SettingsDesignTokens.detailWidth)
        .frame(maxHeight: .infinity)
        .onAppear {
            self.consumePendingSubTab()
        }
        .onChange(of: self.settingsState?.pendingAppearanceSubTab) { _, _ in
            self.consumePendingSubTab()
        }
    }
    
    
    private var subTabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppearanceSubTab.allCases) { tab in
                let isSelected = (self.selectedSubTab == tab)
                Button {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                        self.selectedSubTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                    .fill(self.colorScheme == .dark ? Color.white.opacity(0.14) : Color.white)
                                    .shadow(color: .black.opacity(self.colorScheme == .dark ? 0.20 : 0.06), radius: 1.5, y: 0.5)
                                    .matchedGeometryEffect(id: "appearanceSubTabPill", in: self.subTabNamespace)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(self.colorScheme == .dark ? 0.06 : 0.04))
        )
        .padding(.horizontal, SettingsDesignTokens.contentPadding)
        .padding(.vertical, 10)
    }
    
    
    private func consumePendingSubTab() {
        guard let pending = self.settingsState?.pendingAppearanceSubTab else { return }
        self.selectedSubTab = pending
        self.settingsState?.pendingAppearanceSubTab = nil
    }
}
