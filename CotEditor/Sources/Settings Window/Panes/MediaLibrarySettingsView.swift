//
//  MediaLibrarySettingsView.swift
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

// MARK: - Shared Import Utility

@MainActor
enum UserMediaLibraryImporter {
    
    static func presentImageFilePicker(
        preferredKind: UserMediaKind,
        onImported: @escaping @MainActor (MediaLibraryImportResult) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = preferredKind == .avatar
            ? AppLanguage.text("上传头像图片", en: "Upload Avatar Images")
            : AppLanguage.text("上传背景图片", en: "Upload Background Images")
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            let urls = panel.urls
            Task { @MainActor in
                let result = UserMediaLibraryStore.shared.importURLs(urls, preferredKind: preferredKind)
                onImported(result)
            }
        }
    }
    
    
    static func presentFolderPicker(
        preferredKind: UserMediaKind,
        onImported: @escaping @MainActor (MediaLibraryImportResult) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = AppLanguage.text("导入图片文件夹", en: "Import Image Folder")
        panel.message = AppLanguage.text(
            "可选择单个图片文件夹，或同时包含 avatars 与 bgs 子目录的总目录",
            en: "Select a folder of images or a parent folder containing avatars/ and bgs/ subfolders"
        )
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            let urls = panel.urls
            Task { @MainActor in
                let result = UserMediaLibraryStore.shared.importURLs(urls, preferredKind: preferredKind)
                onImported(result)
            }
        }
    }
    
    
    static func extractDroppedURLs(from providers: [NSItemProvider]) async -> (urls: [URL], images: [NSImage]) {
        var urls: [URL] = []
        var images: [NSImage] = []
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let url = await Self.loadFileURL(from: provider) {
                    urls.append(url)
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                if let image = await Self.loadNSImage(from: provider) {
                    images.append(image)
                }
            }
        }
        return (urls, images)
    }
    
    
    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil)
                {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    
    private static func loadNSImage(from provider: NSItemProvider) async -> NSImage? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                continuation.resume(returning: object as? NSImage)
            }
        }
    }
    
    
    @discardableResult
    static func handleDrop(
        providers: [NSItemProvider],
        preferredKind: UserMediaKind,
        onImported: @escaping @MainActor (MediaLibraryImportResult) -> Void
    ) -> Bool {
        let supported = providers.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) || $0.canLoadObject(ofClass: NSImage.self)
        }
        guard supported else { return false }
        
        Task { @MainActor in
            let payload = await Self.extractDroppedURLs(from: providers)
            var aggregated = MediaLibraryImportResult()
            if !payload.urls.isEmpty {
                let r = UserMediaLibraryStore.shared.importURLs(payload.urls, preferredKind: preferredKind)
                aggregated.avatarsAdded += r.avatarsAdded
                aggregated.backgroundsAdded += r.backgroundsAdded
                aggregated.skippedDuplicates += r.skippedDuplicates
                aggregated.failedCount += r.failedCount
                aggregated.firstAddedAvatarID = aggregated.firstAddedAvatarID ?? r.firstAddedAvatarID
                aggregated.firstAddedBackgroundID = aggregated.firstAddedBackgroundID ?? r.firstAddedBackgroundID
            }
            for (idx, image) in payload.images.enumerated() {
                let outcome = UserMediaLibraryStore.shared.addImage(
                    image,
                    title: preferredKind == .avatar ? "拖入头像 \(idx + 1)" : "拖入背景 \(idx + 1)",
                    kind: preferredKind
                )
                if outcome.isDuplicate {
                    aggregated.skippedDuplicates += 1
                } else if let asset = outcome.asset {
                    switch preferredKind {
                        case .avatar:
                            aggregated.avatarsAdded += 1
                            aggregated.firstAddedAvatarID = aggregated.firstAddedAvatarID ?? asset.id
                        case .background:
                            aggregated.backgroundsAdded += 1
                            aggregated.firstAddedBackgroundID = aggregated.firstAddedBackgroundID ?? asset.id
                    }
                } else {
                    aggregated.failedCount += 1
                }
            }
            onImported(aggregated)
        }
        return true
    }
}


// MARK: - Settings Pane View

struct MediaLibrarySettingsView: View {
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var library = UserMediaLibraryStore.shared
    @State private var wallpaperManager = WallpaperManager.shared
    @State private var activeTab: UserMediaKind = .avatar
    @State private var isDropTargeted = false
    @State private var hoveredAssetID: String?
    @State private var statusBanner: String?
    
    private var cardBackground: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.055) : Color.white
    }
    
    private var cardBorder: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08)
    }
    
    
    var body: some View {
        let _ = self.library.revision
        let _ = self.wallpaperManager.catalogVersion
        
        VStack(spacing: 0) {
            self.headerControls
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 12)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let statusBanner = self.statusBanner {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                            Text(statusBanner)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button {
                                withAnimation(.easeOut(duration: 0.14)) {
                                    self.statusBanner = nil
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 0.8)
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    switch self.activeTab {
                        case .avatar:
                            self.avatarLibrarySection
                        case .background:
                            self.boardAssignmentsCard
                            self.backgroundLibrarySection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .overlay {
            if self.isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 4]))
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        VStack(spacing: 6) {
                            Text(AppLanguage.text(
                                "松手导入到\(self.activeTab == .avatar ? "头像库" : "背景库")",
                                en: "Drop to Import"
                            ))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(12)
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: self.$isDropTargeted) { providers in
            UserMediaLibraryImporter.handleDrop(providers: providers, preferredKind: self.activeTab) { result in
                self.handleImportCompleted(result)
            }
        }
    }
    
    
    private var headerControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("", selection: self.$activeTab) {
                    Text(AppLanguage.text("头像库 (\(self.library.avatars.count))", en: "Avatars (\(self.library.avatars.count))"))
                        .tag(UserMediaKind.avatar)
                    Text(AppLanguage.text("背景库 (\(self.library.backgrounds.count))", en: "Backgrounds (\(self.library.backgrounds.count))"))
                        .tag(UserMediaKind.background)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                
                Spacer(minLength: 8)
                
                Button {
                    UserMediaLibraryImporter.presentFolderPicker(preferredKind: self.activeTab) { result in
                        self.handleImportCompleted(result)
                    }
                } label: {
                    Label(AppLanguage.text("导入文件夹", en: "Import Folder"), systemImage: "folder.badge.plus")
                }
                .controlSize(.small)
                
                Button {
                    UserMediaLibraryImporter.presentImageFilePicker(preferredKind: self.activeTab) { result in
                        self.handleImportCompleted(result)
                    }
                } label: {
                    Label(AppLanguage.text("上传图片", en: "Upload"), systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            Text(AppLanguage.text(
                "统一管理个人头像与背景素材；可将文件夹直接拖入此处，若包含 avatars / bgs 子目录将自动分库。",
                en: "Manage your avatar and background assets. Drop files or folders here; avatars/ and bgs/ subfolders sort automatically."
            ))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    
    // MARK: - Avatars Grid
    
    @ViewBuilder
    private var avatarLibrarySection: some View {
        if self.library.avatars.isEmpty {
            self.emptyLibraryCard(
                symbol: "person.crop.circle.badge.plus",
                title: AppLanguage.text("头像库还是空的", en: "Avatar Library is Empty"),
                subtitle: AppLanguage.text(
                    "上传任意头像图片或导入整个头像文件夹后，即可一键分配给所有 Bot 与个人账户。",
                    en: "Upload images or import a folder to assign custom avatars to Bots and your user profile."
                )
            )
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 112, maximum: 136), spacing: 10)],
                spacing: 10
            ) {
                ForEach(self.library.avatars) { asset in
                    self.avatarCard(asset)
                }
            }
        }
    }
    
    
    private func avatarCard(_ asset: UserMediaAsset) -> some View {
        let isHovered = (self.hoveredAssetID == asset.id)
        let thumb = self.library.thumbnailImage(for: asset, maxPixelSize: 280)
        
        return VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumb {
                        Image(nsImage: thumb)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 74, height: 74)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(isHovered ? 0.24 : 0.10), lineWidth: 1)
                )
                
                if isHovered {
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            self.library.deleteAsset(id: asset.id, kind: .avatar)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white, Color.black.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                    .help(AppLanguage.text("从头像库移除", en: "Delete Avatar"))
                    .offset(x: 4, y: -2)
                }
            }
            .padding(.top, 4)
            
            Text(asset.title)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
            
            Menu {
                ForEach(AIBotID.allCases) { botID in
                    Button {
                        if self.library.applyAvatar(assetID: asset.id, to: botID) {
                            self.showStatus("✓ 已将「\(asset.title)」设为 \(botID.displayName) 头像")
                        }
                    } label: {
                        Text(AppLanguage.text("分配给 \(botID.displayName)", en: "Assign to \(botID.displayName)"))
                    }
                }
                Divider()
                Button {
                    if self.library.applyAvatarToActiveUser(assetID: asset.id) {
                        self.showStatus("✓ 已将「\(asset.title)」设为当前用户头像")
                    }
                } label: {
                    Text(AppLanguage.text("设为当前用户头像", en: "Use for Active User"))
                }
            } label: {
                Text(AppLanguage.text("分配头像 ▾", en: "Assign ▾"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Color.accentColor.opacity(0.11), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(self.cardBorder, lineWidth: 0.75)
        )
        .onHover { inside in
            self.hoveredAssetID = inside ? asset.id : (self.hoveredAssetID == asset.id ? nil : self.hoveredAssetID)
        }
    }
    
    
    // MARK: - Board Background Summary & Backgrounds Grid
    
    private var boardAssignmentsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppLanguage.text("看板当前背景", en: "Board Backgrounds"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            
            VStack(spacing: 0) {
                ForEach(Array(BoardBackgroundSlot.allCases.enumerated()), id: \.element.id) { idx, slot in
                    if idx > 0 {
                        Divider().padding(.leading, 12)
                    }
                    self.boardSlotRow(slot)
                }
            }
            .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(self.cardBorder, lineWidth: 0.75)
            )
        }
    }
    
    
    private func boardSlotRow(_ slot: BoardBackgroundSlot) -> some View {
        let assignment = self.library.boardAssignment(for: slot)
        let asset = self.library.boardBackgroundAsset(for: slot)
        let thumb = asset.flatMap { self.library.thumbnailImage(for: $0, maxPixelSize: 160) }
        
        return HStack(spacing: 10) {
            Image(systemName: slot.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            
            Text(slot.title)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 96, alignment: .leading)
            
            if let asset, let assignment {
                HStack(spacing: 6) {
                    if let thumb {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 30, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    Text(asset.title)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 4)
                
                HStack(spacing: 4) {
                    Text(AppLanguage.text("浓度", en: "Opacity"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { assignment.opacity },
                            set: { self.library.updateBoardBackgroundStyle(for: slot, opacity: $0, blurRadius: assignment.blurRadius) }
                        ),
                        in: 0.06...0.55
                    )
                    .frame(width: 64)
                    
                    Text(AppLanguage.text("模糊", en: "Blur"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { assignment.blurRadius },
                            set: { self.library.updateBoardBackgroundStyle(for: slot, opacity: assignment.opacity, blurRadius: $0) }
                        ),
                        in: 0...28
                    )
                    .frame(width: 58)
                }
                
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        self.library.setBoardBackground(assetID: nil, for: slot)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(AppLanguage.text("清除背景", en: "Clear Background"))
            } else {
                Text(AppLanguage.text("未设置（使用主题默认底色）", en: "Default theme surface"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
    }
    
    
    @ViewBuilder
    private var backgroundLibrarySection: some View {
        if self.library.backgrounds.isEmpty {
            self.emptyLibraryCard(
                symbol: "photo.on.rectangle.angled",
                title: AppLanguage.text("背景库还是空的", en: "Background Library is Empty"),
                subtitle: AppLanguage.text(
                    "上传背景图或导入背景文件夹后，可用于编辑器壁纸、数据看板封面以及看盘 / 播客 / 资讯 / 总管看板。",
                    en: "Upload images or import a folder to customize Editor Wallpaper, Dashboard Hero, and all Boards."
                )
            )
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 162, maximum: 210), spacing: 10)],
                spacing: 10
            ) {
                ForEach(self.library.backgrounds) { asset in
                    self.backgroundCard(asset)
                }
            }
        }
    }
    
    
    private func backgroundCard(_ asset: UserMediaAsset) -> some View {
        let isHovered = (self.hoveredAssetID == asset.id)
        let thumb = self.library.thumbnailImage(for: asset, maxPixelSize: 420)
        let isWallpaper = self.wallpaperManager.spec.isEnabled
            && self.wallpaperManager.spec.selectedID == WallpaperManager.mediaLibraryWallpaperID(for: asset.id)
        let assignedBoards = self.library.assignedBoardSlots(forBackgroundID: asset.id)
        
        return VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumb {
                        Image(nsImage: thumb)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                    }
                }
                .frame(height: 98)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if isWallpaper || !assignedBoards.isEmpty {
                        HStack(spacing: 4) {
                            if isWallpaper {
                                Text(AppLanguage.text("壁纸", en: "Wallpaper"))
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor, in: Capsule())
                            }
                            ForEach(assignedBoards.prefix(2)) { slot in
                                Text(slot.shortTitle)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.58), in: Capsule())
                            }
                            if assignedBoards.count > 2 {
                                Text("+\(assignedBoards.count - 2)")
                                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.58), in: Capsule())
                            }
                        }
                        .padding(6)
                    }
                }
                
                if isHovered {
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            self.library.deleteAsset(id: asset.id, kind: .background)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white, Color.black.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                    .padding(5)
                    .help(AppLanguage.text("从背景库移除", en: "Delete Background"))
                }
            }
            
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(asset.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    if asset.pixelWidth > 0, asset.pixelHeight > 0 {
                        Text("\(asset.pixelWidth)×\(asset.pixelHeight)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer(minLength: 4)
                
                Menu {
                    Button {
                        if self.library.applyBackgroundToEditorWallpaper(assetID: asset.id) {
                            self.showStatus("✓ 已将「\(asset.title)」设为编辑器壁纸")
                        }
                    } label: {
                        Label(AppLanguage.text("设为编辑器壁纸", en: "Set as Editor Wallpaper"), systemImage: "macwindow")
                    }
                    
                    Button {
                        if self.library.applyBackgroundToDashboardHero(assetID: asset.id) {
                            self.showStatus("✓ 已将「\(asset.title)」设为数据看板封面")
                        }
                    } label: {
                        Label(AppLanguage.text("设为数据看板封面", en: "Set as Dashboard Cover"), systemImage: "rectangle.topthird.inset.filled")
                    }
                    
                    Divider()
                    
                    ForEach(BoardBackgroundSlot.allCases) { slot in
                        let active = (self.library.boardAssignment(for: slot)?.assetID == asset.id)
                        Button {
                            self.library.setBoardBackground(assetID: asset.id, for: slot)
                            self.showStatus("✓ 已将「\(asset.title)」设为\(slot.title)背景")
                        } label: {
                            Label(
                                active ? "✓ \(slot.title)" : slot.title,
                                systemImage: slot.symbolName
                            )
                        }
                    }
                } label: {
                    Text(AppLanguage.text("应用 ▾", en: "Apply ▾"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Color.accentColor.opacity(0.11), in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(8)
        .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(self.cardBorder, lineWidth: 0.75)
        )
        .onHover { inside in
            self.hoveredAssetID = inside ? asset.id : (self.hoveredAssetID == asset.id ? nil : self.hoveredAssetID)
        }
    }
    
    
    private func emptyLibraryCard(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 10) {
                Button {
                    UserMediaLibraryImporter.presentFolderPicker(preferredKind: self.activeTab) { result in
                        self.handleImportCompleted(result)
                    }
                } label: {
                    Label(AppLanguage.text("导入文件夹", en: "Import Folder"), systemImage: "folder.badge.plus")
                }
                .controlSize(.regular)
                
                Button {
                    UserMediaLibraryImporter.presentImageFilePicker(preferredKind: self.activeTab) { result in
                        self.handleImportCompleted(result)
                    }
                } label: {
                    Label(AppLanguage.text("上传图片", en: "Upload Images"), systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .padding(.horizontal, 24)
        .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(self.cardBorder, lineWidth: 0.75)
        )
    }
    
    
    private func handleImportCompleted(_ result: MediaLibraryImportResult) {
        if result.avatarsAdded > 0 && result.backgroundsAdded == 0 && self.activeTab != .avatar {
            withAnimation(.easeOut(duration: 0.16)) {
                self.activeTab = .avatar
            }
        } else if result.backgroundsAdded > 0 && result.avatarsAdded == 0 && self.activeTab != .background {
            withAnimation(.easeOut(duration: 0.16)) {
                self.activeTab = .background
            }
        }
        self.showStatus(result.summaryText)
    }
    
    
    private func showStatus(_ text: String) {
        withAnimation(.easeOut(duration: 0.16)) {
            self.statusBanner = text
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                if self.statusBanner == text {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.statusBanner = nil
                    }
                }
            }
        }
    }
}


// MARK: - Reusable Library Popovers & Board Backdrop

struct AvatarLibraryPickerPopover: View {
    
    var title: String = AppLanguage.text("从头像库选择", en: "Choose from Avatar Library")
    let onSelect: (UserMediaAsset) -> Void
    
    @State private var library = UserMediaLibraryStore.shared
    
    var body: some View {
        let _ = self.library.revision
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(self.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    UserMediaLibraryImporter.presentFolderPicker(preferredKind: .avatar) { _ in }
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .controlSize(.small)
                .help(AppLanguage.text("导入头像文件夹", en: "Import Folder"))
                
                Button {
                    UserMediaLibraryImporter.presentImageFilePicker(preferredKind: .avatar) { _ in }
                } label: {
                    Label(AppLanguage.text("上传", en: "Upload"), systemImage: "plus")
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            if self.library.avatars.isEmpty {
                Text(AppLanguage.text("暂无头像", en: "No avatars"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                        spacing: 10
                    ) {
                        ForEach(self.library.avatars) { asset in
                            let thumb = self.library.thumbnailImage(for: asset, maxPixelSize: 200)
                            Button {
                                self.onSelect(asset)
                            } label: {
                                VStack(spacing: 4) {
                                    Group {
                                        if let thumb {
                                            Image(nsImage: thumb)
                                                .resizable()
                                                .interpolation(.high)
                                                .scaledToFill()
                                        } else {
                                            Circle().fill(Color.primary.opacity(0.1))
                                        }
                                    }
                                    .frame(width: 58, height: 58)
                                    .clipShape(Circle())
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))
                                    
                                    Text(asset.title)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 270)
            }
        }
        .padding(12)
        .frame(width: 344)
    }
}


struct BackgroundLibraryPickerPopover: View {
    
    var title: String = AppLanguage.text("从背景库选择", en: "Choose from Background Library")
    var slot: BoardBackgroundSlot? = nil
    var activeAssetID: String? = nil
    let onSelect: (UserMediaAsset) -> Void
    var onClear: (() -> Void)? = nil
    
    @State private var library = UserMediaLibraryStore.shared
    
    var body: some View {
        let _ = self.library.revision
        let slotAssignment = self.slot.flatMap { self.library.boardAssignment(for: $0) }
        let effectiveActiveID = self.activeAssetID ?? slotAssignment?.assetID
        
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(self.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    UserMediaLibraryImporter.presentFolderPicker(preferredKind: .background) { _ in }
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .controlSize(.small)
                .help(AppLanguage.text("导入背景文件夹", en: "Import Folder"))
                
                Button {
                    UserMediaLibraryImporter.presentImageFilePicker(preferredKind: .background) { _ in }
                } label: {
                    Label(AppLanguage.text("上传", en: "Upload"), systemImage: "plus")
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
            
            if let slot = self.slot, let assignment = slotAssignment {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Text(AppLanguage.text("浓度", en: "Opacity"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { assignment.opacity },
                                set: { self.library.updateBoardBackgroundStyle(for: slot, opacity: $0, blurRadius: assignment.blurRadius) }
                            ),
                            in: 0.06...0.55
                        )
                        
                        Text(AppLanguage.text("模糊", en: "Blur"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { assignment.blurRadius },
                                set: { self.library.updateBoardBackgroundStyle(for: slot, opacity: assignment.opacity, blurRadius: $0) }
                            ),
                            in: 0...28
                        )
                    }
                    
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            self.library.setBoardBackground(assetID: nil, for: slot)
                            self.onClear?()
                        } label: {
                            Label(AppLanguage.text("恢复默认底色", en: "Use Default Surface"), systemImage: "trash")
                        }
                        .controlSize(.mini)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if let onClear = self.onClear {
                HStack {
                    Spacer()
                    Button(role: .destructive, action: onClear) {
                        Label(AppLanguage.text("清除当前背景", en: "Clear Background"), systemImage: "trash")
                    }
                    .controlSize(.mini)
                }
            }
            
            Divider()
            
            if self.library.backgrounds.isEmpty {
                Text(AppLanguage.text("暂无背景", en: "No backgrounds"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                        spacing: 8
                    ) {
                        ForEach(self.library.backgrounds) { asset in
                            let thumb = self.library.thumbnailImage(for: asset, maxPixelSize: 360)
                            let isSelected = (effectiveActiveID == asset.id)
                            Button {
                                self.onSelect(asset)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    ZStack(alignment: .topTrailing) {
                                        Group {
                                            if let thumb {
                                                Image(nsImage: thumb)
                                                    .resizable()
                                                    .interpolation(.high)
                                                    .scaledToFill()
                                            } else {
                                                Rectangle().fill(Color.primary.opacity(0.1))
                                            }
                                        }
                                        .frame(height: 82)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .strokeBorder(
                                                    isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                                    lineWidth: isSelected ? 2 : 0.75
                                                )
                                        )
                                        
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.white, Color.accentColor)
                                                .padding(4)
                                        }
                                    }
                                    
                                    Text(asset.title)
                                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? .primary : .secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(12)
        .frame(width: 396)
    }
}


struct BoardBackgroundBackdropView: View {
    
    let slot: BoardBackgroundSlot
    let baseSurface: Color
    let isDark: Bool
    
    @State private var library = UserMediaLibraryStore.shared
    
    var body: some View {
        let _ = self.library.revision
        ZStack {
            self.baseSurface
            
            if let assignment = self.library.boardAssignment(for: self.slot),
               let bgImage = self.library.boardBackgroundImage(for: self.slot)
            {
                GeometryReader { geo in
                    Image(nsImage: bgImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: assignment.blurRadius)
                        .clipped()
                        .opacity(assignment.opacity)
                }
                .allowsHitTesting(false)
            }
        }
    }
}
