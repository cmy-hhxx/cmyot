//
//  SidebarProfileSettingsPane.swift
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

/// Personal profile, multi-account switcher, and local storage/migration controls.
struct SidebarProfileSettingsPane: View {
    
    let onExportDatabase: () -> Void
    let onImportDatabase: () -> Void
    var onResetAllConfiguration: (() -> Void)? = nil
    var refreshRevision: Int = 0
    var isMigrating: Bool = false
    var migrationStatus: String? = nil
    
    @State private var profileManager = UserProfileManager.shared
    @State private var isCreatingUser = false
    @State private var newUserName = ""
    @State private var newUserAvatarData: Data?
    @State private var newUserAvatarImage: NSImage?
    @State private var copyCurrentAIConfig = true
    @State private var confirmDeleteID: String?
    @State private var editingActiveName = ""
    @State private var isEditingActiveName = false
    @State private var isShowingActiveAvatarLibrary = false
    @State private var isShowingNewUserAvatarLibrary = false
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            SettingsGroupCard(title: AppLanguage.text("本地账户", en: "Local Account")) {
                self.activeProfileRow
                
                if self.isCreatingUser {
                    SettingsRowDivider()
                    self.newUserForm
                }
                
                if self.profileManager.profiles.count > 1 {
                    SettingsRowDivider()
                    self.profilesList
                }
            }
            
            LocalDatabaseSettingsView(
                onExportDatabase: self.onExportDatabase,
                onImportDatabase: self.onImportDatabase,
                onResetAllConfiguration: self.onResetAllConfiguration,
                refreshRevision: self.refreshRevision,
                isMigrating: self.isMigrating,
                migrationStatus: self.migrationStatus
            )
        }
    }
    
    
    private var activeProfileRow: some View {
        let active = self.profileManager.activeProfile
        return HStack(spacing: 12) {
            Button {
                self.pickAvatar(forActive: true)
            } label: {
                UserAvatarCircleView(profile: active, size: 42)
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                    }
            }
            .buttonStyle(.plain)
            .help(AppLanguage.text("更换当前账户头像", en: "Change Avatar"))
            
            if self.isEditingActiveName {
                HStack(spacing: 6) {
                    TextField(AppLanguage.text("昵称", en: "Name"), text: self.$editingActiveName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .onSubmit { self.commitActiveRename() }
                    Button(AppLanguage.text("保存", en: "Save")) { self.commitActiveRename() }
                        .controlSize(.small)
                    Button(AppLanguage.text("取消", en: "Cancel")) { self.isEditingActiveName = false }
                        .controlSize(.small)
                }
            } else {
                HStack(spacing: 6) {
                    Text(active.displayName)
                        .font(.system(size: 13.5, weight: .semibold))
                    Button {
                        self.editingActiveName = active.displayName
                        self.isEditingActiveName = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
            
            Button {
                self.isShowingActiveAvatarLibrary.toggle()
            } label: {
                Label(AppLanguage.text("头像库", en: "Avatars"), systemImage: "photo.stack")
            }
            .controlSize(.small)
            .popover(isPresented: self.$isShowingActiveAvatarLibrary, arrowEdge: .bottom) {
                AvatarLibraryPickerPopover { asset in
                    _ = UserMediaLibraryStore.shared.applyAvatarToActiveUser(assetID: asset.id, profileManager: self.profileManager)
                    self.isShowingActiveAvatarLibrary = false
                }
            }
            
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    self.isCreatingUser.toggle()
                }
            } label: {
                Label(AppLanguage.text("新建用户", en: "New User"), systemImage: "person.badge.plus")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    
    private var newUserForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    self.pickAvatar(forActive: false)
                } label: {
                    let previewHex = UserProfileManager.avatarPresetColors[self.profileManager.profiles.count % UserProfileManager.avatarPresetColors.count]
                    UserAvatarCircleView(
                        profile: UserProfile(
                            id: "draft",
                            displayName: self.newUserName.isEmpty ? "新" : self.newUserName,
                            avatarData: self.newUserAvatarData,
                            avatarColorHex: previewHex,
                            dbFilename: "",
                            accountKind: "local",
                            email: nil,
                            remoteUserID: nil,
                            createdAt: Date(),
                            lastActiveAt: Date()
                        ),
                        size: 30,
                        customImage: self.newUserAvatarImage
                    )
                }
                .buttonStyle(.plain)
                .help(AppLanguage.text("选择新账户头像", en: "Choose Avatar"))
                
                TextField(AppLanguage.text("新用户昵称", en: "Display name"), text: self.$newUserName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { self.submitNewUser() }
                
                Button {
                    self.isShowingNewUserAvatarLibrary.toggle()
                } label: {
                    Image(systemName: "photo.stack")
                }
                .controlSize(.small)
                .help(AppLanguage.text("从头像库选择", en: "Choose from Library"))
                .popover(isPresented: self.$isShowingNewUserAvatarLibrary, arrowEdge: .bottom) {
                    AvatarLibraryPickerPopover { asset in
                        if let img = UserMediaLibraryStore.shared.fullImage(for: asset),
                           let data = UserProfileManager.processedAvatarPNGData(from: img),
                           let processed = NSImage(data: data)
                        {
                            self.newUserAvatarData = data
                            self.newUserAvatarImage = processed
                        }
                        self.isShowingNewUserAvatarLibrary = false
                    }
                }
                
                Button {
                    self.newUserName = GeneratedDocumentName.generateCandidate()
                } label: {
                    Image(systemName: "dice")
                }
                .controlSize(.small)
                .help(AppLanguage.text("随机昵称", en: "Random Name"))
                
                Button(AppLanguage.text("创建", en: "Create")) {
                    self.submitNewUser()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            HStack {
                Text(AppLanguage.text("同步当前模型配置", en: "Copy AI Gateways"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: self.$copyCurrentAIConfig)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    
    private var profilesList: some View {
        let active = self.profileManager.activeProfile
        return VStack(spacing: 0) {
            ForEach(Array(self.profileManager.profiles.enumerated()), id: \.element.id) { idx, profile in
                if idx > 0 {
                    SettingsRowDivider()
                }
                let isCurrent = (profile.id == active.id)
                HStack(spacing: 8) {
                    UserAvatarCircleView(profile: profile, size: 22)
                    Text(profile.displayName)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    Spacer()
                    if isCurrent {
                        Text(AppLanguage.text("使用中", en: "Active"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Button(AppLanguage.text("切换", en: "Switch")) {
                            self.confirmDeleteID = nil
                            self.profileManager.switchToProfile(id: profile.id)
                        }
                        .controlSize(.small)
                        
                        let isConfirming = (self.confirmDeleteID == profile.id)
                        Button(isConfirming ? AppLanguage.text("确认删除", en: "Confirm") : AppLanguage.text("删除", en: "Delete"), role: .destructive) {
                            if isConfirming {
                                self.profileManager.deleteProfile(id: profile.id)
                                self.confirmDeleteID = nil
                            } else {
                                self.confirmDeleteID = profile.id
                            }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: SettingsDesignTokens.rowHeight)
            }
        }
    }
    
    
    private func commitActiveRename() {
        let trimmed = self.editingActiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            self.profileManager.updateProfile(id: self.profileManager.activeProfile.id, displayName: trimmed)
        }
        self.isEditingActiveName = false
    }
    
    
    private func submitNewUser() {
        let name = self.newUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = UserProfileManager.avatarPresetColors[self.profileManager.profiles.count % UserProfileManager.avatarPresetColors.count]
        self.profileManager.createProfile(
            displayName: name.isEmpty ? GeneratedDocumentName.generateCandidate() : name,
            avatarData: self.newUserAvatarData,
            avatarColorHex: color,
            copyCurrentAIEndpoints: self.copyCurrentAIConfig,
            switchImmediately: true
        )
        self.newUserName = ""
        self.newUserAvatarData = nil
        self.newUserAvatarImage = nil
        self.isCreatingUser = false
    }
    
    
    private func pickAvatar(forActive: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let image = NSImage(contentsOf: url),
                  let data = UserProfileManager.processedAvatarPNGData(from: image),
                  let processed = NSImage(data: data)
            else { return }
            Task { @MainActor in
                _ = UserMediaLibraryStore.shared.importURLs([url], preferredKind: .avatar)
                if forActive {
                    self.profileManager.updateProfile(id: self.profileManager.activeProfile.id, avatarData: .some(data))
                } else {
                    self.newUserAvatarData = data
                    self.newUserAvatarImage = processed
                }
            }
        }
    }
}
