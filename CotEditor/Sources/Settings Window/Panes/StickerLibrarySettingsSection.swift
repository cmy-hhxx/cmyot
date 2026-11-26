//
//  StickerLibrarySettingsSection.swift
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
import SwiftUI
import UniformTypeIdentifiers

struct StickerLibrarySettingsSection: View {
    
    let onStatusMessage: (String) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var store = CotStickerLibraryStore.shared
    @State private var searchQuery = ""
    @State private var selectedCategory = "all"
    @State private var onlyFavorites = false
    @State private var editingSticker: StickerAsset?
    @State private var showOnlineSearch = false
    
    private var cardBackground: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.055) : Color.white
    }
    
    private var cardBorder: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08)
    }
    
    private var filteredStickers: [StickerAsset] {
        let catFilter: String? = self.selectedCategory == "all" ? nil : self.selectedCategory
        return self.store.search(
            query: self.searchQuery,
            onlyFavorites: self.onlyFavorites,
            categoryFilter: catFilter,
            limit: 600
        )
    }
    
    
    var body: some View {
        let _ = self.store.revision
        VStack(alignment: .leading, spacing: 12) {
            self.toolbarRow
            self.categoryStrip
            self.stickerGrid
        }
        .sheet(item: self.$editingSticker) { sticker in
            StickerSemanticEditorSheet(sticker: sticker) {
                self.editingSticker = nil
            }
        }
        .sheet(isPresented: self.$showOnlineSearch) {
            OnlineStickerSearchSheet(onImported: { count in
                if count > 0 {
                    self.onStatusMessage(AppLanguage.text("已入库 \(count) 张在线表情", en: "Imported \(count) online stickers"))
                }
            })
        }
    }
    
    
    private var toolbarRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField(AppLanguage.text("搜索", en: "Search"), text: self.$searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                if !self.searchQuery.isEmpty {
                    Button {
                        self.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 0.8))
            
            Button {
                self.showOnlineSearch = true
            } label: {
                Label(AppLanguage.text("在线搜图", en: "Online"), systemImage: "globe")
            }
            .controlSize(.small)
            
            Button {
                Task {
                    let count = await self.store.annotateMissingWithVisionAI(limit: 16)
                    self.onStatusMessage(
                        count > 0
                            ? AppLanguage.text("AI 已补全 \(count) 张语义标签", en: "Tagged \(count) stickers")
                            : AppLanguage.text("暂无可补全或未配置视觉模型", en: "No unannotated stickers or vision model")
                    )
                }
            } label: {
                if self.store.isAnnotatingWithAI {
                    ProgressView().controlSize(.small)
                } else {
                    Label(AppLanguage.text("AI 补全语义", en: "AI Tag"), systemImage: "tag")
                }
            }
            .controlSize(.small)
            .disabled(self.store.isAnnotatingWithAI)
            
            Button {
                Self.presentStickerUploadPicker { msg in
                    self.onStatusMessage(msg)
                }
            } label: {
                Label(AppLanguage.text("上传表情", en: "Upload"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
    
    
    private var categoryStrip: some View {
        let counts = self.store.categoryCounts()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                self.filterPill(
                    title: AppLanguage.text("全部", en: "All"),
                    count: self.store.stickers.count,
                    isActive: self.selectedCategory == "all" && !self.onlyFavorites
                ) {
                    self.selectedCategory = "all"
                    self.onlyFavorites = false
                }
                
                self.filterPill(
                    title: AppLanguage.text("收藏", en: "Favorites"),
                    count: self.store.stickers.filter(\.isFavorite).count,
                    isActive: self.onlyFavorites
                ) {
                    self.onlyFavorites.toggle()
                    if self.onlyFavorites { self.selectedCategory = "all" }
                }
                
                ForEach(StickerCategory.allCases) { cat in
                    let count = counts[cat.rawValue] ?? 0
                    if count > 0 || cat == .custom {
                        self.filterPill(
                            title: cat.displayName,
                            count: count,
                            isActive: self.selectedCategory == cat.rawValue && !self.onlyFavorites
                        ) {
                            self.onlyFavorites = false
                            self.selectedCategory = cat.rawValue
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    
    private func filterPill(title: String, count: Int, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .opacity(0.72)
            }
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                isActive ? Color.primary.opacity(0.10) : self.cardBackground,
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(isActive ? Color.primary.opacity(0.24) : self.cardBorder, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
    
    
    @ViewBuilder
    private var stickerGrid: some View {
        let items = self.filteredStickers
        if items.isEmpty {
            VStack(spacing: 10) {
                Text(AppLanguage.text("暂无表情包", en: "No Stickers"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 0.8))
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 112, maximum: 136), spacing: 10)],
                spacing: 10
            ) {
                ForEach(items) { sticker in
                    StickerGridCell(
                        sticker: sticker,
                        cardBackground: self.cardBackground,
                        cardBorder: self.cardBorder,
                        onEdit: { self.editingSticker = sticker },
                        onToggleFavorite: { self.store.toggleFavorite(id: sticker.id) },
                        onDelete: { self.store.deleteSticker(id: sticker.id) }
                    )
                }
            }
        }
    }
    
    
    static func presentStickerUploadPicker(
        allowDirectories: Bool = false,
        defaultCategory: String = "custom",
        onCompleted: @escaping @MainActor (String) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = allowDirectories
            ? AppLanguage.text("导入表情文件夹", en: "Import Sticker Folder")
            : AppLanguage.text("上传表情包", en: "Upload Stickers")
        panel.allowedContentTypes = [.image, .png, .jpeg, .gif, .webP, .heic]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = allowDirectories
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            let urls = panel.urls
            Task { @MainActor in
                let result = await CotStickerLibraryStore.shared.importFiles(urls, defaultCategory: defaultCategory)
                onCompleted(result.summaryText)
            }
        }
    }
}


private struct StickerGridCell: View {
    
    let sticker: StickerAsset
    let cardBackground: Color
    let cardBorder: Color
    let onEdit: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    
    @State private var store = CotStickerLibraryStore.shared
    @State private var isHovered = false
    
    var body: some View {
        let _ = self.store.revision
        let thumb = self.store.cachedOrLoadThumbnail(for: self.sticker, maxPixelSize: 200)
        
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Button(action: self.onEdit) {
                    ZStack {
                        if let thumb {
                            Image(nsImage: thumb)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                        } else {
                            Color.primary.opacity(0.05)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 92)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .clipped()
                }
                .buttonStyle(.plain)
                
                HStack(spacing: 4) {
                    if self.sticker.isAnimated {
                        Text("GIF")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.black.opacity(0.56), in: Capsule())
                    }
                    if self.isHovered || self.sticker.isFavorite {
                        Button(action: self.onToggleFavorite) {
                            Image(systemName: self.sticker.isFavorite ? "star.fill" : "star")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(self.sticker.isFavorite ? Color.orange : Color.white)
                                .padding(4)
                                .background(Color.black.opacity(0.52), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(5)
            }
            
            HStack(spacing: 4) {
                Text(self.sticker.searchableSummary)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if self.isHovered {
                    Button(role: .destructive, action: self.onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(self.isHovered ? Color.primary.opacity(0.24) : self.cardBorder, lineWidth: 0.8)
        )
        .onHover { self.isHovered = $0 }
    }
}


private struct StickerSemanticEditorSheet: View {
    
    let sticker: StickerAsset
    let onDismiss: () -> Void
    
    @State private var store = CotStickerLibraryStore.shared
    @State private var category: String
    @State private var ocrText: String
    @State private var meaning: String
    @State private var tagsText: String
    @State private var selectedMoods: Set<String>
    
    private static let moodOptions = ["开心", "兴奋", "平静", "专注", "摸鱼", "无语", "委屈"]
    
    init(sticker: StickerAsset, onDismiss: @escaping () -> Void) {
        self.sticker = sticker
        self.onDismiss = onDismiss
        self._category = State(initialValue: sticker.category)
        self._ocrText = State(initialValue: sticker.ocrText)
        self._meaning = State(initialValue: sticker.meaning)
        self._tagsText = State(initialValue: sticker.tags.joined(separator: " "))
        self._selectedMoods = State(initialValue: Set(sticker.moods))
    }
    
    var body: some View {
        let thumb = self.store.cachedOrLoadThumbnail(for: self.sticker, maxPixelSize: 320)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Group {
                    if let thumb {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Color.primary.opacity(0.06)
                    }
                }
                .frame(width: 96, height: 96)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                
                VStack(alignment: .leading, spacing: 8) {
                    Picker(AppLanguage.text("分类", en: "Category"), selection: self.$category) {
                        ForEach(StickerCategory.allCases) { cat in
                            Text(cat.displayName).tag(cat.rawValue)
                        }
                    }
                    TextField(AppLanguage.text("含义", en: "Meaning"), text: self.$meaning)
                        .textFieldStyle(.roundedBorder)
                    TextField(AppLanguage.text("图上文字", en: "OCR Text"), text: self.$ocrText)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLanguage.text("情绪标签", en: "Moods"))
                    .font(.system(size: 12, weight: .semibold))
                HStack(spacing: 6) {
                    ForEach(Self.moodOptions, id: \.self) { mood in
                        let active = self.selectedMoods.contains(mood)
                        Button {
                            if active { self.selectedMoods.remove(mood) } else { self.selectedMoods.insert(mood) }
                        } label: {
                            Text(mood)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLanguage.text("检索词", en: "Tags"))
                    .font(.system(size: 12, weight: .semibold))
                TextField(AppLanguage.text("空格分隔", en: "Space separated"), text: self.$tagsText)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Button(role: .destructive) {
                    self.store.deleteSticker(id: self.sticker.id)
                    self.onDismiss()
                } label: {
                    Text(AppLanguage.text("删除", en: "Delete"))
                }
                Spacer()
                Button(AppLanguage.text("取消", en: "Cancel"), action: self.onDismiss)
                Button(AppLanguage.text("保存", en: "Save")) {
                    let tags = self.tagsText
                        .components(separatedBy: CharacterSet.whitespacesAndNewlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    self.store.updateSemantics(
                        id: self.sticker.id,
                        category: self.category,
                        ocrText: self.ocrText,
                        meaning: self.meaning,
                        moods: Array(self.selectedMoods),
                        tags: tags
                    )
                    self.onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 460)
    }
}
