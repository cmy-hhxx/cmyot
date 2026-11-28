//
//  SidebarAppearanceSubPanes.swift
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
import Defaults
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 1. 配色 (Theme & Color Palettes)

struct SidebarAppearanceThemePane: View {
    
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(.documentAppearance) private var documentAppearance
    @AppStorage(.windowAlpha) private var windowAlpha
    @State private var studioPalette = StudioPaletteManager.shared
    
    
    var body: some View {
        let isDark = (self.colorScheme == .dark)
        let activePreview = self.studioPalette.softPreviewColors(for: self.studioPalette.selectedID, isDark: isDark)
        
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            SettingsGroupCard(title: AppLanguage.text("外观", en: "Appearance")) {
                AppearanceModeThumbnailsRow(
                    selectedMode: self.documentAppearance,
                    accent: activePreview.swatch,
                    isDark: isDark
                ) { newMode in
                    withAnimation(.easeInOut(duration: 0.22)) {
                        self.studioPalette.applyAppearanceMode(newMode)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            
            SettingsGroupCard(title: AppLanguage.text("主题配色", en: "Color Palettes")) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(StudioPaletteID.allCases) { preset in
                        AppearancePaletteCard(
                            preset: preset,
                            preview: self.studioPalette.softPreviewColors(for: preset, isDark: isDark),
                            isSelected: self.studioPalette.selectedID == preset,
                            isDark: isDark
                        ) {
                            withAnimation(.easeInOut(duration: 0.20)) {
                                self.studioPalette.selectPalette(preset, syncEditorTheme: true)
                            }
                        }
                    }
                }
                .padding(12)
            }
            
            SettingsGroupCard(title: AppLanguage.text("窗口透明度与光标", en: "Window & Cursor")) {
                SettingsItemRow(label: AppLanguage.text("窗口不透明度", en: "Window Opacity")) {
                    HStack(spacing: 8) {
                        Slider(value: self.$windowAlpha, in: 0.2...1.0)
                            .frame(width: SettingsDesignTokens.sliderWidth)
                        Text(self.windowAlpha, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: SettingsDesignTokens.readoutWidth, alignment: .trailing)
                    }
                    .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("光标颜色", en: "Insertion Point")) {
                    CustomCursorColorControl()
                }
            }
        }
    }
}


private struct AppearanceModeThumbnailsRow: View {
    
    let selectedMode: AppearanceMode
    let accent: Color
    let isDark: Bool
    let onSelect: (AppearanceMode) -> Void
    
    private static let orderedModes: [AppearanceMode] = [.light, .dark, .default]
    
    var body: some View {
        HStack(spacing: 14) {
            ForEach(Self.orderedModes, id: \.self) { mode in
                AppearanceModeThumbnailCard(
                    mode: mode,
                    isSelected: self.selectedMode == mode,
                    accent: self.accent,
                    isDark: self.isDark,
                    onSelect: { self.onSelect(mode) }
                )
            }
        }
    }
}


private struct AppearanceModeThumbnailCard: View {
    
    let mode: AppearanceMode
    let isSelected: Bool
    let accent: Color
    let isDark: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    private var title: String {
        switch self.mode {
            case .light: AppLanguage.text("浅色", en: "Light")
            case .dark: AppLanguage.text("深色", en: "Dark")
            case .default: AppLanguage.text("自动", en: "Auto")
        }
    }
    
    var body: some View {
        Button(action: self.onSelect) {
            VStack(spacing: 7) {
                self.thumbnailArtwork
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                self.isDark
                                    ? Color.white.opacity(self.isHovered ? 0.16 : 0.10)
                                    : Color.black.opacity(self.isHovered ? 0.14 : 0.08),
                                lineWidth: 0.6
                            )
                    )
                    .padding(2.5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10.5, style: .continuous)
                            .strokeBorder(
                                self.isSelected ? self.accent.opacity(0.82) : Color.clear,
                                lineWidth: 1.75
                            )
                    )
                
                Text(self.title)
                    .font(.system(size: 12, weight: self.isSelected ? .semibold : .regular))
                    .foregroundStyle(self.isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }
    
    
    @ViewBuilder
    private var thumbnailArtwork: some View {
        switch self.mode {
            case .light:
                self.miniDesktopMockup(dark: false)
            case .dark:
                self.miniDesktopMockup(dark: true)
            case .default:
                HStack(spacing: 0) {
                    self.miniDesktopMockup(dark: false)
                    self.miniDesktopMockup(dark: true)
                }
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 0.5)
                )
        }
    }
    
    
    private func miniDesktopMockup(dark: Bool) -> some View {
        let backdropTop = dark
            ? Color(red: 0.20, green: 0.22, blue: 0.27)
            : Color(red: 0.90, green: 0.93, blue: 0.97)
        let backdropBottom = dark
            ? Color(red: 0.25, green: 0.27, blue: 0.33)
            : Color(red: 0.95, green: 0.96, blue: 0.98)
        let windowSurface = dark
            ? Color(red: 0.21, green: 0.215, blue: 0.24)
            : Color.white
        let sidebarSurface = dark
            ? Color(red: 0.255, green: 0.26, blue: 0.29)
            : Color(red: 0.955, green: 0.96, blue: 0.975)
        let lineColor = dark ? Color.white.opacity(0.20) : Color.black.opacity(0.11)
        let faintLine = dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
        
        return ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [backdropTop, backdropBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 2.5) {
                        Circle().fill(Color(red: 0.90, green: 0.48, blue: 0.45).opacity(0.75)).frame(width: 3.5, height: 3.5)
                        Circle().fill(Color(red: 0.92, green: 0.74, blue: 0.38).opacity(0.75)).frame(width: 3.5, height: 3.5)
                        Circle().fill(Color(red: 0.45, green: 0.78, blue: 0.52).opacity(0.75)).frame(width: 3.5, height: 3.5)
                    }
                    RoundedRectangle(cornerRadius: 1.5).fill(lineColor).frame(width: 14, height: 2.5)
                    RoundedRectangle(cornerRadius: 1.5).fill(faintLine).frame(width: 10, height: 2.5)
                    Spacer(minLength: 0)
                }
                .padding(.top, 5)
                .padding(.leading, 5)
                .frame(width: 26, alignment: .leading)
                .frame(maxHeight: .infinity)
                .background(sidebarSurface)
                
                VStack(alignment: .leading, spacing: 4.5) {
                    RoundedRectangle(cornerRadius: 1.5).fill(self.accent.opacity(dark ? 0.65 : 0.55)).frame(width: 22, height: 3)
                    RoundedRectangle(cornerRadius: 1.5).fill(lineColor).frame(maxWidth: .infinity).frame(height: 2.5)
                    RoundedRectangle(cornerRadius: 1.5).fill(faintLine).frame(width: 34, height: 2.5)
                    Spacer(minLength: 0)
                }
                .padding(.top, 7)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(windowSurface)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(dark ? 0.22 : 0.07), radius: 3, y: 1)
            .padding(.top, 9)
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.bottom, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


private struct AppearancePaletteCard: View {
    
    let preset: StudioPaletteID
    let preview: StudioPalettePreviewColors
    let isSelected: Bool
    let isDark: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        let cardFill: Color = if self.isSelected {
            self.isDark ? Color.white.opacity(0.08) : Color.white
        } else if self.isHovered {
            self.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.032)
        } else {
            self.isDark ? Color.white.opacity(0.025) : Color.black.opacity(0.016)
        }
        
        let borderStroke: Color = if self.isSelected {
            self.preview.swatch.opacity(self.isDark ? 0.58 : 0.48)
        } else if self.isHovered {
            self.isDark ? Color.white.opacity(0.13) : Color.black.opacity(0.10)
        } else {
            self.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
        }
        
        Button(action: self.onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                AppearancePalettePreviewStrip(preview: self.preview, isDark: self.isDark)
                
                HStack(spacing: 7) {
                    Circle()
                        .fill(self.preview.swatch)
                        .frame(width: 9, height: 9)
                        .overlay(
                            Circle()
                                .strokeBorder(self.isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.10), lineWidth: 0.5)
                        )
                    
                    Text(self.preset.displayName)
                        .font(.system(size: 12.5, weight: self.isSelected ? .semibold : .regular))
                        .foregroundStyle(Color.primary.opacity(self.isSelected ? 1.0 : 0.86))
                        .lineLimit(1)
                    
                    Spacer(minLength: 4)
                    
                    if self.isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(self.preview.swatch)
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(cardFill)
                    .shadow(
                        color: (self.isSelected && !self.isDark) ? Color.black.opacity(0.05) : Color.clear,
                        radius: 4,
                        y: 1.5
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderStroke, lineWidth: self.isSelected ? 1.15 : 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }
}


private struct AppearancePalettePreviewStrip: View {
    
    let preview: StudioPalettePreviewColors
    let isDark: Bool
    
    var body: some View {
        ZStack(alignment: .leading) {
            self.preview.canvas
            
            LinearGradient(
                colors: [self.preview.ambientWash, Color.clear],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(self.preview.accent.opacity(0.75)).frame(width: 18, height: 3.5)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(self.preview.lineSecondary).frame(width: 24, height: 2.5)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(self.preview.lineSecondary).frame(width: 15, height: 2.5)
                }
                .padding(.horizontal, 7)
                .frame(width: 44, alignment: .leading)
                .frame(maxHeight: .infinity)
                .background(self.preview.sidebar)
                
                Rectangle()
                    .fill(self.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                    .frame(width: 0.5)
                
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(self.preview.accent.opacity(0.82)).frame(width: 28, height: 3.5)
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(self.preview.linePrimary).frame(width: 46, height: 3)
                    }
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(self.preview.linePrimary).frame(maxWidth: 118).frame(height: 3)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(self.preview.lineSecondary).frame(maxWidth: 78).frame(height: 3)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(self.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.055), lineWidth: 0.5)
        )
    }
}


// MARK: - 2. 图标 (App Icon Studio)

struct SidebarAppIconSettingsPane: View {
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var iconManager = AppIconManager.shared
    @State private var isDropTargeted = false
    @State private var dragStartOffset: CGSize?
    
    private var customRimBinding: Binding<Color> {
        Binding(
            get: { StudioPaletteManager.swiftUIColor(hex: self.iconManager.spec.customBorderHex) },
            set: { newColor in
                self.iconManager.updateSpecLive { spec in
                    spec.customBorderHex = StudioPaletteManager.hexString(from: NSColor(newColor))
                }
            }
        )
    }
    
    private var matColorBinding: Binding<Color> {
        Binding(
            get: { StudioPaletteManager.swiftUIColor(hex: self.iconManager.spec.backgroundMatHex) },
            set: { newColor in
                self.iconManager.updateSpecLive { spec in
                    spec.backgroundMatHex = StudioPaletteManager.hexString(from: NSColor(newColor))
                }
            }
        )
    }
    
    
    var body: some View {
        let _ = self.iconManager.customImageVersion
        let _ = self.iconManager.previewRevision
        
        VStack(spacing: 0) {
            self.pinnedDockPreview
                .padding(.horizontal, SettingsDesignTokens.contentPadding)
                .padding(.top, 14)
                .padding(.bottom, 12)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
                    self.iconSourceCard
                    self.iconFrameCard
                    self.iconStyleCard
                }
                .padding(.horizontal, SettingsDesignTokens.contentPadding)
                .padding(.vertical, 16)
            }
        }
    }
    
    
    private var pinnedDockPreview: some View {
        SettingsGroupCard(title: nil) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: self.colorScheme == .dark
                                    ? [Color(red: 0.12, green: 0.13, blue: 0.18), Color(red: 0.08, green: 0.09, blue: 0.13)]
                                    : [Color(red: 0.90, green: 0.91, blue: 0.95), Color(red: 0.84, green: 0.86, blue: 0.91)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 246, height: 34)
                        .offset(y: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(Color.white.opacity(self.colorScheme == .dark ? 0.14 : 0.45), lineWidth: 0.6)
                                .frame(width: 246, height: 34)
                                .offset(y: 38)
                        )
                        .shadow(color: .black.opacity(self.colorScheme == .dark ? 0.35 : 0.10), radius: 10, y: 4)
                    
                    HStack(alignment: .bottom, spacing: 14) {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 44, height: 44)
                            .offset(y: -4)
                        
                        Image(nsImage: self.iconManager.previewImage)
                            .resizable()
                            .interpolation(.high)
                            .id(self.iconManager.previewRevision)
                            .frame(width: 96, height: 96)
                            .scaleEffect(self.isDropTargeted ? 1.06 : 1.0)
                            .animation(.spring(response: 0.24, dampingFraction: 0.76), value: self.isDropTargeted)
                        
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 44, height: 44)
                            .offset(y: -4)
                    }
                    .offset(y: 4)
                    
                    WallpaperFramingInteractionOverlay(
                        isInteractive: true,
                        onDragStart: {
                            self.dragStartOffset = CGSize(
                                width: self.iconManager.spec.imageOffsetX,
                                height: self.iconManager.spec.imageOffsetY
                            )
                        },
                        onDragChanged: { translation in
                            let base = self.dragStartOffset ?? .zero
                            self.iconManager.updateSpecLive { spec in
                                spec.imageOffsetX = base.width + Double(translation.width) / 140.0
                                spec.imageOffsetY = base.height - Double(translation.height) / 140.0
                            }
                        },
                        onDragEnd: { self.dragStartOffset = nil },
                        onDropTargetedChange: { targeted in self.isDropTargeted = targeted },
                        onDropURLs: { urls in
                            if let first = urls.first(where: { NSImage(contentsOf: $0) != nil }),
                               let image = NSImage(contentsOf: first)
                            {
                                _ = self.iconManager.saveCustomImage(image)
                            }
                        },
                        onDropImages: { images in
                            if let first = images.first {
                                _ = self.iconManager.saveCustomImage(first)
                            }
                        }
                    )
                }
                .frame(height: 124)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            self.isDropTargeted ? Color.accentColor : Color.clear,
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                        )
                        .allowsHitTesting(false)
                )
                
                HStack(spacing: 8) {
                    Text(self.iconManager.spec.borderStyle.displayName)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.05), in: Capsule())
                    
                    Text("\(Int((self.iconManager.spec.imageZoom * 100).rounded()))%")
                        .font(.system(size: 11.5, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.05), in: Capsule())
                    
                    Spacer()
                    
                    if abs(self.iconManager.spec.imageOffsetX) > 0.01 || abs(self.iconManager.spec.imageOffsetY) > 0.01 {
                        Button(AppLanguage.text("画面居中", en: "Center")) {
                            self.iconManager.updateSpecLive { spec in
                                spec.imageOffsetX = 0
                                spec.imageOffsetY = 0
                            }
                        }
                        .controlSize(.small)
                    }
                    
                    Button(AppLanguage.text("恢复默认", en: "Reset")) {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)) {
                            self.iconManager.resetToDefault()
                        }
                    }
                    .controlSize(.small)
                    
                    Button(AppLanguage.text("上传图片", en: "Upload")) {
                        self.pickCustomArtwork()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(12)
        }
    }
    
    
    private var iconSourceCard: some View {
        SettingsGroupCard(title: AppLanguage.text("图标", en: "Icon")) {
            HStack(spacing: 10) {
                ForEach(AppIconSource.allCases) { source in
                    let isSelected = (self.iconManager.spec.source == source)
                    let thumb = self.iconManager.sourceImage(for: source)
                    
                    Button {
                        if source == .customImage && !self.iconManager.hasCustomImage {
                            self.pickCustomArtwork()
                            return
                        }
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                            self.iconManager.updateSpecLive { $0.source = source }
                        }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                if let thumb {
                                    Image(nsImage: thumb)
                                        .resizable()
                                        .interpolation(.high)
                                        .scaledToFill()
                                } else {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? Color.accentColor : Color.primary.opacity(0.10),
                                        lineWidth: isSelected ? 2.0 : 0.5
                                    )
                            )
                            
                            Text(source.displayName)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.045) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(10)
        }
    }
    
    
    private var iconFrameCard: some View {
        SettingsGroupCard(title: AppLanguage.text("边框", en: "Frame")) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
                    ForEach(AppIconBorderStyle.allCases) { style in
                        let isSelected = (self.iconManager.spec.borderStyle == style)
                        Button {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                                self.iconManager.updateSpecLive { spec in
                                    spec.borderStyle = style
                                    if style != .clean && spec.borderWidth < 1.5 {
                                        spec.borderWidth = 4.6
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: style.previewColors,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                                
                                Text(style.displayName)
                                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                                    .fixedSize()
                            }
                            .padding(.horizontal, 9)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? Color.primary.opacity(self.colorScheme == .dark ? 0.12 : 0.07) : Color.primary.opacity(0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.70) : Color.clear, lineWidth: 1.2)
                            )
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
                
                if self.iconManager.spec.borderStyle == .customColor {
                    HStack {
                        Text(AppLanguage.text("自定义镶边颜色", en: "Custom Rim Color"))
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                        Spacer()
                        ColorPicker("", selection: self.customRimBinding, supportsOpacity: false)
                            .labelsHidden()
                    }
                    .padding(.top, 2)
                }
            }
            .padding(12)
        }
    }
    
    
    private var iconStyleCard: some View {
        SettingsGroupCard(title: AppLanguage.text("样式", en: "Style")) {
            SettingsItemRow(label: AppLanguage.text("镶边粗细", en: "Border Width")) {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { self.iconManager.spec.borderWidth },
                            set: { newValue in
                                self.iconManager.updateSpecLive { spec in
                                    spec.borderWidth = newValue
                                    if newValue > 0.25 && spec.borderStyle == .clean {
                                        spec.borderStyle = .goldInlay
                                    }
                                }
                            }
                        ),
                        in: 0...10
                    )
                    .frame(width: SettingsDesignTokens.sliderWidth)
                    Text(String(format: "%.1f", self.iconManager.spec.borderWidth))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: SettingsDesignTokens.readoutWidth, alignment: .trailing)
                }
                .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
            }
            
            SettingsRowDivider()
            
            SettingsItemRow(label: AppLanguage.text("画面缩放", en: "Artwork Zoom")) {
                HStack(spacing: 8) {
                    Slider(value: self.specBinding(\.imageZoom), in: 0.80...1.35)
                        .frame(width: SettingsDesignTokens.sliderWidth)
                    Text("\(Int((self.iconManager.spec.imageZoom * 100).rounded()))%")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: SettingsDesignTokens.readoutWidth, alignment: .trailing)
                }
                .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
            }
            
            SettingsRowDivider()
            
            SettingsItemRow(label: AppLanguage.text("圆角曲率", en: "Corner Curvature")) {
                HStack(spacing: 8) {
                    Slider(value: self.specBinding(\.cornerRoundness), in: 0.16...0.50)
                        .frame(width: SettingsDesignTokens.sliderWidth)
                    Text("\(Int((self.iconManager.spec.cornerRoundness * 100).rounded()))%")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: SettingsDesignTokens.readoutWidth, alignment: .trailing)
                }
                .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
            }
            
            SettingsRowDivider()
            
            SettingsItemRow(label: AppLanguage.text("表面水晶流光", en: "Crystal Gloss")) {
                HStack(spacing: 8) {
                    Slider(value: self.specBinding(\.glossIntensity), in: 0.0...1.0)
                        .frame(width: SettingsDesignTokens.sliderWidth)
                    Text("\(Int((self.iconManager.spec.glossIntensity * 100).rounded()))%")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: SettingsDesignTokens.readoutWidth, alignment: .trailing)
                }
                .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
            }
            
            if self.iconManager.spec.imageZoom < 0.99 {
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("画布衬底色", en: "Background Mat")) {
                    ColorPicker("", selection: self.matColorBinding, supportsOpacity: false)
                        .labelsHidden()
                }
            }
        }
    }
    
    
    private func specBinding<T: Equatable>(_ keyPath: WritableKeyPath<AppIconSpec, T>) -> Binding<T> {
        Binding(
            get: { self.iconManager.spec[keyPath: keyPath] },
            set: { newValue in
                self.iconManager.updateSpecLive { spec in
                    spec[keyPath: keyPath] = newValue
                }
            }
        )
    }
    
    
    private func pickCustomArtwork() {
        let panel = NSOpenPanel()
        panel.title = AppLanguage.text("选择应用图标图片", en: "Choose App Icon Image")
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK,
                  let url = panel.url,
                  let image = NSImage(contentsOf: url)
            else { return }
            Task { @MainActor in
                _ = self.iconManager.saveCustomImage(image)
            }
        }
    }
}


// MARK: - 3. 壁纸 (Wallpaper Studio)

struct SidebarWallpaperSettingsPane: View {
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var manager = WallpaperManager.shared
    @State private var mediaLibrary = UserMediaLibraryStore.shared
    @State private var hoveredID: String?
    @State private var isDropTargeted = false
    @State private var dragStartFraming: WallpaperFraming?
    @State private var isFramingActive = false
    @State private var showViewfinderGrid = false
    
    
    var body: some View {
        let _ = self.manager.catalogVersion
        let _ = self.mediaLibrary.revision
        let items = self.manager.allItems
        let selectedItem = items.first { $0.id == self.manager.spec.selectedID } ?? items.first
        let framing = self.manager.spec.currentFraming
        
        VStack(spacing: 0) {
            self.pinnedPreviewSection(selectedItem: selectedItem, framing: framing)
            Divider()
            self.scrollableControlsSection(items: items)
        }
    }
    
    
    private func pinnedPreviewSection(selectedItem: WallpaperItem?, framing: WallpaperFraming) -> some View {
        VStack(spacing: 0) {
            SettingsGroupCard(title: nil) {
                VStack(spacing: 10) {
                    self.liveEditorPreviewStage(selectedItem: selectedItem)
                        .frame(height: 184)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    self.isDropTargeted
                                        ? StudioPaletteManager.shared.activeAccentColor
                                        : ((self.isFramingActive || self.showViewfinderGrid)
                                            ? StudioPaletteManager.shared.activeAccentColor.opacity(0.65)
                                            : (self.colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))),
                                    style: self.isDropTargeted
                                        ? StrokeStyle(lineWidth: 2, dash: [6, 4])
                                        : StrokeStyle(lineWidth: (self.isFramingActive || self.showViewfinderGrid) ? 1.3 : 0.75)
                                )
                                .allowsHitTesting(false)
                        )
                    
                    HStack(spacing: 7) {
                        if let selectedItem {
                            Circle().fill(Color(hexString: selectedItem.accentHex)).frame(width: 7, height: 7)
                            Text(selectedItem.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                        }
                        
                        Picker("", selection: Binding(
                            get: { self.manager.spec.displayMode },
                            set: { mode in
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                                    self.manager.updateFraming(displayMode: mode)
                                }
                            }
                        )) {
                            ForEach(WallpaperDisplayMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 144)
                        
                        Spacer(minLength: 4)
                        
                        Button {
                            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                                self.showViewfinderGrid.toggle()
                            }
                        } label: {
                            Image(systemName: self.showViewfinderGrid ? "viewfinder.circle.fill" : "viewfinder")
                        }
                        .controlSize(.small)
                        .tint(self.showViewfinderGrid ? StudioPaletteManager.shared.activeAccentColor : nil)
                        .help(AppLanguage.text("构图网格", en: "Grid"))
                        
                        if !framing.isDefault {
                            Button(AppLanguage.text("重置", en: "Reset")) {
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)) {
                                    self.manager.resetFraming()
                                }
                            }
                            .controlSize(.small)
                        }
                        
                        if let selectedItem, selectedItem.isCustom {
                            Button(role: .destructive) {
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                                    self.manager.deleteCustomWallpaper(id: selectedItem.id)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .controlSize(.small)
                            .help(AppLanguage.text("删除壁纸", en: "Delete"))
                        }
                        
                        Button {
                            UserMediaLibraryImporter.presentFolderPicker(preferredKind: .background) { result in
                                if let firstID = result.firstAddedBackgroundID {
                                    _ = self.mediaLibrary.applyBackgroundToEditorWallpaper(assetID: firstID, wallpaperManager: self.manager)
                                }
                            }
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .controlSize(.small)
                        .help(AppLanguage.text("导入背景文件夹", en: "Import Background Folder"))
                        
                        Button {
                            self.pickCustomWallpaperImage()
                        } label: {
                            Label(AppLanguage.text("上传", en: "Upload"), systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(12)
            }
        }
        .padding(.horizontal, SettingsDesignTokens.contentPadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
    
    
    private func scrollableControlsSection(items: [WallpaperItem]) -> some View {
        let zoomRange = self.manager.spec.displayMode.minScale...WallpaperDisplayMode.maxScale
        
        return ScrollView {
            VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
                SettingsGroupCard(title: AppLanguage.text("画面调整", en: "Framing & Display")) {
                    SettingsItemRow(label: AppLanguage.text("启用编辑器壁纸", en: "Enable Wallpaper")) {
                        Toggle("", isOn: Binding(
                            get: { self.manager.spec.isEnabled },
                            set: { val in
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                                    self.manager.spec.isEnabled = val
                                }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    
                    SettingsRowDivider()
                    
                    SettingsItemRow(label: AppLanguage.text("缩放比例", en: "Zoom")) {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(get: { self.manager.spec.scale }, set: { self.manager.updateFraming(scale: $0) }),
                                in: zoomRange
                            )
                            .frame(width: SettingsDesignTokens.sliderWidth)
                            .disabled(!self.manager.spec.isEnabled)
                            
                            Text("\(Int((self.manager.spec.scale * 100).rounded()))%")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: SettingsDesignTokens.readoutWidth, alignment: .trailing)
                        }
                        .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                    }
                    
                    SettingsRowDivider()
                    
                    SettingsItemRow(label: AppLanguage.text("画面浓度", en: "Opacity")) {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(get: { self.manager.spec.opacity }, set: { self.manager.spec.opacity = $0 }),
                                in: 0.04...0.85
                            )
                            .frame(width: SettingsDesignTokens.sliderWidth)
                            .disabled(!self.manager.spec.isEnabled)
                            
                            Text("\(Int((self.manager.spec.opacity * 100).rounded()))%")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: SettingsDesignTokens.readoutWidth, alignment: .trailing)
                        }
                        .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                    }
                    
                    SettingsRowDivider()
                    
                    SettingsItemRow(label: AppLanguage.text("柔焦模糊", en: "Soft Blur")) {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(get: { self.manager.spec.blurRadius }, set: { self.manager.spec.blurRadius = $0 }),
                                in: 0...40
                            )
                            .frame(width: SettingsDesignTokens.sliderWidth)
                            .disabled(!self.manager.spec.isEnabled)
                            
                            Text("\(Int(self.manager.spec.blurRadius.rounded())) px")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: SettingsDesignTokens.readoutWidth, alignment: .trailing)
                        }
                        .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                    }
                }
                
                if !self.mediaLibrary.backgrounds.isEmpty {
                    SettingsGroupCard(title: AppLanguage.text("我的背景库", en: "My Background Library")) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(self.mediaLibrary.backgrounds) { asset in
                                self.backgroundLibraryTile(asset)
                            }
                        }
                        .padding(12)
                    }
                }
                
                SettingsGroupCard(title: AppLanguage.text("精选壁纸", en: "Gallery")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(items) { item in
                            self.wallpaperTile(item)
                        }
                    }
                    .padding(12)
                }
            }
            .padding(.horizontal, SettingsDesignTokens.contentPadding)
            .padding(.vertical, 16)
        }
    }
    
    
    @ViewBuilder
    private func liveEditorPreviewStage(selectedItem: WallpaperItem?) -> some View {
        let isDark = (self.colorScheme == .dark)
        let editorBase = isDark ? Color(red: 0.09, green: 0.095, blue: 0.11) : Color(red: 0.985, green: 0.985, blue: 0.99)
        let studioMat = isDark ? Color(red: 0.055, green: 0.06, blue: 0.075) : Color(red: 0.89, green: 0.90, blue: 0.92)
        let artwork = selectedItem.map { self.manager.artworkImage(for: $0.id) }
        let accent = selectedItem.map { Color(hexString: $0.accentHex) } ?? StudioPaletteManager.shared.activeAccentColor
        let framingMode = (self.isFramingActive || self.showViewfinderGrid)
        let previewAlpha = framingMode
            ? 0.94
            : (self.manager.spec.isEnabled ? min(0.95, max(0.20, self.manager.spec.opacity * 1.45)) : 0.16)
        let previewBlur = framingMode
            ? 0.0
            : (self.manager.spec.isEnabled ? min(16, self.manager.spec.blurRadius * 0.42) : 0.0)
        let windowAspect = WallpaperManager.referenceWindowAspectRatio()
        
        GeometryReader { outerGeo in
            let viewportRect = MediaAssetCropEditorSheet.fittedCropRect(in: outerGeo.size, aspect: windowAspect, inset: 10)
            let drawInViewport = artwork.map {
                WallpaperManager.framedDrawRect(
                    imageSize: $0.size,
                    viewportSize: viewportRect.size,
                    scale: self.manager.spec.scale,
                    panX: self.manager.spec.panX,
                    panY: self.manager.spec.panY,
                    isFlippedY: true,
                    displayMode: self.manager.spec.displayMode
                )
            } ?? .zero
            
            ZStack(alignment: .topLeading) {
                studioMat
                
                if framingMode, let artwork, !drawInViewport.isEmpty {
                    Image(nsImage: artwork)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: max(1, drawInViewport.width), height: max(1, drawInViewport.height))
                        .position(x: viewportRect.minX + drawInViewport.midX, y: viewportRect.minY + drawInViewport.midY)
                        .opacity(0.24)
                }
                
                ZStack(alignment: .topLeading) {
                    editorBase
                        .overlay(alignment: .topLeading) {
                            if let artwork, !drawInViewport.isEmpty {
                                Image(nsImage: artwork)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: max(1, drawInViewport.width), height: max(1, drawInViewport.height))
                                    .position(x: drawInViewport.midX, y: drawInViewport.midY)
                                    .blur(radius: previewBlur)
                                    .opacity(previewAlpha)
                                    .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20), value: selectedItem?.id)
                            }
                        }
                        .frame(width: viewportRect.width, height: viewportRect.height)
                        .clipped()
                    
                    self.miniEditorChrome(isDark: isDark, accent: accent, framingMode: framingMode)
                        .allowsHitTesting(false)
                    
                    if framingMode {
                        self.viewfinderOverlay(size: viewportRect.size)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: viewportRect.width, height: viewportRect.height)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            framingMode ? accent.opacity(0.92) : (isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.16)),
                            lineWidth: framingMode ? 1.5 : 0.8
                        )
                )
                .shadow(color: Color.black.opacity(isDark ? 0.42 : 0.16), radius: 8, y: 3)
                .offset(x: viewportRect.minX, y: viewportRect.minY)
                
                self.stageOverlay(artwork: artwork, viewportSize: viewportRect.size)
                
                if self.isDropTargeted {
                    ZStack {
                        Color.black.opacity(0.35)
                        Text(AppLanguage.text("松手设为壁纸", en: "Drop to Set Wallpaper"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(accent, in: Capsule())
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
        }
    }
    
    
    private func stageOverlay(artwork: NSImage?, viewportSize: CGSize) -> some View {
        WallpaperFramingInteractionOverlay(
            isInteractive: artwork != nil,
            onDragStart: {
                guard artwork != nil else { return }
                if !self.manager.spec.isEnabled { self.manager.spec.isEnabled = true }
                self.dragStartFraming = self.manager.spec.currentFraming
                self.isFramingActive = true
            },
            onDragChanged: { translation in
                guard let artwork else { return }
                let start = self.dragStartFraming ?? self.manager.spec.currentFraming
                let updated = WallpaperManager.dragUpdatedFraming(
                    start: start,
                    imageSize: artwork.size,
                    viewportSize: viewportSize,
                    translation: translation
                )
                self.manager.updateFraming(
                    scale: updated.scale,
                    panX: updated.panX,
                    panY: updated.panY,
                    displayMode: updated.displayMode
                )
            },
            onDragEnd: {
                self.dragStartFraming = nil
                withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.22)) {
                    self.isFramingActive = false
                }
            },
            onMagnify: { magnificationDelta, phase in
                if !self.manager.spec.isEnabled { self.manager.spec.isEnabled = true }
                if phase == .began { self.isFramingActive = true }
                self.manager.updateFraming(scale: self.manager.spec.scale * (1.0 + Double(magnificationDelta)))
                if phase == .ended || phase == .cancelled {
                    withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.22)) {
                        self.isFramingActive = false
                    }
                }
            },
            onScrollZoom: { delta in
                if !self.manager.spec.isEnabled { self.manager.spec.isEnabled = true }
                self.manager.updateFraming(scale: self.manager.spec.scale * (1.0 + Double(delta)))
            },
            onDoubleClick: {
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)) {
                    if self.manager.spec.currentFraming.isDefault {
                        self.manager.updateFraming(scale: 1.6)
                    } else {
                        self.manager.resetFraming()
                    }
                }
            },
            onDropTargetedChange: { targeted in self.isDropTargeted = targeted },
            onDropURLs: { urls in self.handleDroppedURLs(urls) },
            onDropImages: { images in self.handleDroppedImages(images) }
        )
    }
    
    
    private func miniEditorChrome(isDark: Bool, accent: Color, framingMode: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(Color(red: 0.95, green: 0.37, blue: 0.35)).frame(width: 6, height: 6)
                Circle().fill(Color(red: 0.96, green: 0.74, blue: 0.26)).frame(width: 6, height: 6)
                Circle().fill(Color(red: 0.30, green: 0.78, blue: 0.38)).frame(width: 6, height: 6)
                Spacer()
                Text("\(Int((self.manager.spec.scale * 100).rounded()))%")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .opacity(framingMode ? 0.95 : 0.65)
            }
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(isDark ? Color.black.opacity(0.28) : Color.white.opacity(0.62))
            
            Divider().opacity(0.25)
            
            VStack(alignment: .leading, spacing: 7) {
                self.sampleCodeRow(line: "1", segments: [(accent, 36), (.primary.opacity(0.75), 82), (.secondary.opacity(0.45), 52)])
                self.sampleCodeRow(line: "2", segments: [(.clear, 14), (.primary.opacity(0.65), 98), (accent.opacity(0.75), 44)])
                self.sampleCodeRow(line: "3", segments: [(.clear, 14), (.secondary.opacity(0.50), 120)])
                self.sampleCodeRow(line: "4", segments: [(.clear, 26), (accent.opacity(0.85), 50), (.primary.opacity(0.70), 68)])
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .opacity(framingMode ? 0.14 : 0.96)
            .animation(.timingCurve(0.2, 0, 0, 1, duration: 0.16), value: framingMode)
            
            Spacer(minLength: 0)
        }
    }
    
    
    private func viewfinderOverlay(size: CGSize) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Path { path in
                for i in 1...2 {
                    let x = size.width * CGFloat(i) / 3.0
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    let y = size.height * CGFloat(i) / 3.0
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.36), lineWidth: 0.75)
            
            Text("\(self.manager.spec.displayMode.label) · \(Int((self.manager.spec.scale * 100).rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.58), in: Capsule())
                .padding(8)
        }
    }
    
    
    private func sampleCodeRow(line: String, segments: [(Color, CGFloat)]) -> some View {
        HStack(spacing: 8) {
            Text(line).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 14, alignment: .trailing)
            HStack(spacing: 5) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    if seg.0 == .clear {
                        Color.clear.frame(width: seg.1, height: 6)
                    } else {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(seg.0).frame(width: seg.1, height: 6)
                    }
                }
            }
        }
    }
    
    
    private func wallpaperTile(_ item: WallpaperItem) -> some View {
        let isSelected = (self.manager.spec.selectedID == item.id)
        let isHovered = (self.hoveredID == item.id)
        let accent = Color(hexString: item.accentHex)
        let thumb = self.manager.thumbnailImage(for: item.id)
        
        return Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                self.manager.selectWallpaper(id: item.id, enableIfDisabled: true)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: thumb)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(height: 64)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    isSelected ? accent : Color.primary.opacity(isHovered ? 0.22 : 0.08),
                                    lineWidth: isSelected ? 2 : 0.75
                                )
                        )
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white, accent)
                            .padding(4)
                    }
                }
                Text(item.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { inside in
            self.hoveredID = inside ? item.id : (self.hoveredID == item.id ? nil : self.hoveredID)
        }
    }
    
    
    private func backgroundLibraryTile(_ asset: UserMediaAsset) -> some View {
        let libWallpaperID = WallpaperManager.mediaLibraryWallpaperID(for: asset.id)
        let isSelected = (self.manager.spec.selectedID == libWallpaperID)
        let isHovered = (self.hoveredID == libWallpaperID)
        let accent = StudioPaletteManager.shared.activeAccentColor
        let thumb = self.mediaLibrary.thumbnailImage(for: asset, maxPixelSize: 320)
        
        return Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                _ = self.mediaLibrary.applyBackgroundToEditorWallpaper(assetID: asset.id, wallpaperManager: self.manager)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let thumb {
                            Image(nsImage: thumb).resizable().interpolation(.medium).scaledToFill()
                        } else {
                            Rectangle().fill(Color.primary.opacity(0.08))
                        }
                    }
                    .frame(height: 64)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? accent : Color.primary.opacity(isHovered ? 0.22 : 0.08),
                                lineWidth: isSelected ? 2 : 0.75
                            )
                    )
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white, accent)
                            .padding(4)
                    }
                }
                Text(asset.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { inside in
            self.hoveredID = inside ? libWallpaperID : (self.hoveredID == libWallpaperID ? nil : self.hoveredID)
        }
    }
    
    
    private func pickCustomWallpaperImage() {
        let panel = NSOpenPanel()
        panel.title = AppLanguage.text("选择壁纸图片", en: "Choose Wallpaper Image")
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            let urls = panel.urls
            Task { @MainActor in
                self.handleDroppedURLs(urls)
            }
        }
    }
    
    
    private func handleDroppedURLs(_ urls: [URL]) {
        let result = self.mediaLibrary.importURLs(urls, preferredKind: .background)
        if let firstID = result.firstAddedBackgroundID {
            _ = self.mediaLibrary.applyBackgroundToEditorWallpaper(assetID: firstID, wallpaperManager: self.manager)
            return
        }
        if let firstURL = urls.first {
            let outcome = self.mediaLibrary.addImage(from: firstURL, kind: .background)
            if let existing = outcome.asset {
                _ = self.mediaLibrary.applyBackgroundToEditorWallpaper(assetID: existing.id, wallpaperManager: self.manager)
            } else {
                _ = self.manager.saveCustomWallpaper(from: firstURL)
            }
        }
    }
    
    
    private func handleDroppedImages(_ images: [NSImage]) {
        guard let first = images.first else { return }
        let title = "自定义壁纸 \(self.manager.customRecords.count + 1)"
        let outcome = self.mediaLibrary.addImage(first, title: title, kind: .background)
        if let asset = outcome.asset {
            _ = self.mediaLibrary.applyBackgroundToEditorWallpaper(assetID: asset.id, wallpaperManager: self.manager)
        } else {
            _ = self.manager.saveCustomWallpaper(first, title: title)
        }
    }
}


// MARK: - 4. 动效 (Editor Motion)

struct SidebarEffectsSettingsPane: View {
    
    @State private var typewriterEnabled = true
    @State private var typewriterStyle: TypingEffectPreset = .powerMode
    @State private var vimCursorTrailEnabled = true
    @State private var autoPersonalityEnabled = true
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            SettingsGroupCard(title: AppLanguage.text("编辑器动效", en: "Editor Motion")) {
                SettingsItemRow(label: AppLanguage.text("打字粒子特效", en: "Typing Particles")) {
                    Toggle("", isOn: self.$typewriterEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: self.typewriterEnabled) { _, val in
                            CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
                            UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
                        }
                }
                
                if self.typewriterEnabled {
                    SettingsRowDivider()
                    
                    SettingsItemRow(label: AppLanguage.text("粒子风格", en: "Particle Style")) {
                        Picker("", selection: self.$typewriterStyle) {
                            ForEach(TypingEffectPreset.allCases) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                        .onChange(of: self.typewriterStyle) { _, val in
                            CotLocalDatabase.shared.set(val.rawValue, forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle)
                            UserDefaults.standard.set(val.rawValue, forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle)
                        }
                    }
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("Vim 流体光标尾迹", en: "Vim Fluid Cursor Trail")) {
                    Toggle("", isOn: self.$vimCursorTrailEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: self.vimCursorTrailEnabled) { _, val in
                            CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
                            UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
                        }
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("头像环绕弹幕", en: "Avatar Orbit Tags")) {
                    Toggle("", isOn: self.$autoPersonalityEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: self.autoPersonalityEnabled) { _, val in
                            CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.aiPersonalityAutoEnabled)
                        }
                }
            }
        }
        .onAppear {
            let db = CotLocalDatabase.shared
            self.typewriterEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled, default: true)
            self.typewriterStyle = TypingEffectPreset.resolve(
                db.string(forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle, default: TypingEffectPreset.powerMode.rawValue)
            )
            self.vimCursorTrailEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled, default: true)
            self.autoPersonalityEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.aiPersonalityAutoEnabled, default: true)
        }
    }
}
