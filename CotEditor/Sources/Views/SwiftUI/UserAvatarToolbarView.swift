//
//  UserAvatarToolbarView.swift
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

extension Color {
    
    /// Creates a color from a `#RRGGBB` hex string, defaulting to accent blue on parse failure.
    init(hexString: String) {
        
        let raw = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        guard Scanner(string: raw).scanHexInt64(&value), raw.count == 6 else {
            self = .accentColor
            return
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}


/// Reusable circular avatar view displaying either a cropped photo or a tinted monogram.
struct UserAvatarCircleView: View {
    
    let profile: UserProfile
    let size: CGFloat
    var customImage: NSImage?
    
    @State private var manager = UserProfileManager.shared
    
    
    var body: some View {
        let resolvedImage = self.customImage ?? self.manager.avatarImage(for: self.profile)
        let baseColor = Color(hexString: self.profile.avatarColorHex)
        
        ZStack {
            if let resolvedImage {
                Image(nsImage: resolvedImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [baseColor.opacity(0.95), baseColor.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(UserProfileManager.initials(for: self.profile.displayName))
                    .font(.system(size: max(10, self.size * 0.42), weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .frame(width: self.size, height: self.size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(.primary.opacity(0.14), lineWidth: 1)
        )
    }
}


private struct UserAvatarToolbarBadgeLabel: View {
    
    @State private var manager = UserProfileManager.shared
    @State private var isHovered = false
    
    
    var body: some View {
        UserAvatarCircleView(profile: self.manager.activeProfile, size: 24)
            .scaleEffect(self.isHovered ? 1.05 : 1.0)
            .animation(.easeOut(duration: 0.14), value: self.isHovered)
            .onHover { self.isHovered = $0 }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
    }
}


/// Top-right toolbar avatar control that opens the local user profile & account switcher popover.
@MainActor final class UserAvatarToolbarButtonView: NSView {
    
    private let hostingView: NSHostingView<UserAvatarToolbarBadgeLabel>
    private let clickButton = NSButton()
    private var popover: NSPopover?
    private var profileObserver: (any NSObjectProtocol)?
    
    
    override init(frame frameRect: NSRect) {
        
        self.hostingView = NSHostingView(rootView: UserAvatarToolbarBadgeLabel())
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        
        self.translatesAutoresizingMaskIntoConstraints = false
        
        self.hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.hostingView)
        
        self.clickButton.translatesAutoresizingMaskIntoConstraints = false
        self.clickButton.title = ""
        self.clickButton.isBordered = false
        self.clickButton.isTransparent = true
        self.clickButton.focusRingType = .none
        self.clickButton.target = self
        self.clickButton.action = #selector(self.togglePopover(_:))
        self.addSubview(self.clickButton)
        
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: 28),
            self.heightAnchor.constraint(equalToConstant: 28),
            self.hostingView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.hostingView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.hostingView.topAnchor.constraint(equalTo: self.topAnchor),
            self.hostingView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.clickButton.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.clickButton.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.clickButton.topAnchor.constraint(equalTo: self.topAnchor),
            self.clickButton.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
        
        self.refreshTooltip()
        self.profileObserver = NotificationCenter.default.addObserver(
            forName: UserProfileManager.activeProfileDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshTooltip()
            }
        }
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    isolated deinit {
        
        if let profileObserver = self.profileObserver {
            NotificationCenter.default.removeObserver(profileObserver)
        }
    }
    
    
    override var intrinsicContentSize: NSSize {
        
        NSSize(width: 28, height: 28)
    }
    
    
    private func refreshTooltip() {
        
        let name = UserProfileManager.shared.activeProfile.displayName
        let tip = "当前用户：\(name)（点击切换或管理账户）"
        self.toolTip = tip
        self.clickButton.toolTip = tip
    }
    
    
    @objc private func togglePopover(_ sender: Any?) {
        
        if let popover = self.popover, popover.isShown {
            popover.performClose(sender)
            return
        }
        
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let rootView = UserProfilePopoverView(
            hostWindow: self.window,
            closePopover: { [weak popover] in
                popover?.performClose(nil)
            }
        )
        popover.contentViewController = NSHostingController(rootView: rootView)
        popover.show(relativeTo: self.bounds, of: self, preferredEdge: .maxY)
        self.popover = popover
    }
}


/// Popover UI for customizing the active user's avatar/name and switching between isolated local users.
struct UserProfilePopoverView: View {
    
    var hostWindow: NSWindow?
    var closePopover: () -> Void = {}
    
    @State private var manager = UserProfileManager.shared
    @State private var editingName = ""
    @State private var isCreatingUser = false
    @State private var newUserName = ""
    @State private var newUserColorHex = UserProfileManager.avatarPresetColors[1]
    @State private var newUserAvatarData: Data?
    @State private var copyCurrentAIConfig = true
    @State private var confirmDeleteUserID: String?
    
    
    var body: some View {
        let active = self.manager.activeProfile
        
        VStack(alignment: .leading, spacing: 14) {
            // Active User Header & Avatar Upload
            HStack(spacing: 12) {
                Button {
                    self.pickAvatarForActiveUser()
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        UserAvatarCircleView(profile: active, size: 52)
                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: 2, y: 2)
                    }
                }
                .buttonStyle(.plain)
                .help("点击上传头像图片")
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        TextField("输入名称", text: self.$editingName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .onSubmit {
                                self.saveEditedName()
                            }
                        
                        Button("保存") {
                            self.saveEditedName()
                        }
                        .controlSize(.small)
                        .disabled(!self.hasPendingNameChange)
                    }
                    
                    HStack(spacing: 8) {
                        Button("上传头像") {
                            self.pickAvatarForActiveUser()
                        }
                        .controlSize(.small)
                        
                        if active.avatarData != nil {
                            Button("移除头像", role: .destructive) {
                                self.manager.updateProfile(id: active.id, avatarData: .some(nil))
                            }
                            .controlSize(.small)
                        }
                        
                        Spacer(minLength: 0)
                    }
                }
            }
            
            // Avatar accent color & account status
            HStack(spacing: 8) {
                ForEach(UserProfileManager.avatarPresetColors, id: \.self) { hex in
                    Button {
                        self.manager.updateProfile(id: active.id, avatarColorHex: hex)
                    } label: {
                        Circle()
                            .fill(Color(hexString: hex))
                            .frame(width: 15, height: 15)
                            .overlay(
                                Circle()
                                    .strokeBorder(.white, lineWidth: active.avatarColorHex == hex ? 2 : 0)
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(.primary.opacity(active.avatarColorHex == hex ? 0.45 : 0.12), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer(minLength: 4)
                
                Text("本地独立库")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .lineLimit(1)
            }
            
            HStack(spacing: 6) {
                Image(systemName: "person.badge.shield.checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("数据随当前用户独立保存，云端登录功能即将支持")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Button {
                let targetWindow = self.hostWindow
                self.closePopover()
                AnalyticsDashboardWindowController.shared.showInWindow(preferredWindow: targetWindow)
            } label: {
                HStack {
                    Image(systemName: "chart.bar.xaxis")
                    Text("打开个人数据看板")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.regular)
            
            Divider()
            
            // Local Account Switcher
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("切换本地用户")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(self.manager.profiles.count) 个账户")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(self.manager.profiles) { profile in
                            self.userSwitchRow(profile, isActive: profile.id == active.id)
                        }
                    }
                }
                .frame(maxHeight: 144)
            }
            
            Divider()
            
            // Create New Local User
            if self.isCreatingUser {
                VStack(alignment: .leading, spacing: 8) {
                    Text("新建本地用户")
                        .font(.subheadline.weight(.medium))
                    
                    HStack(spacing: 8) {
                        Button {
                            self.pickAvatarForNewUser()
                        } label: {
                            UserAvatarCircleView(
                                profile: UserProfile(
                                    id: "preview",
                                    displayName: self.newUserName.isEmpty ? "新" : self.newUserName,
                                    avatarData: self.newUserAvatarData,
                                    avatarColorHex: self.newUserColorHex,
                                    dbFilename: "",
                                    accountKind: "local",
                                    email: nil,
                                    remoteUserID: nil,
                                    createdAt: Date(),
                                    lastActiveAt: Date()
                                ),
                                size: 30,
                                customImage: self.newUserAvatarData.flatMap { NSImage(data: $0) }
                            )
                        }
                        .buttonStyle(.plain)
                        .help("选择新用户头像")
                        
                        TextField("输入新用户名称", text: self.$newUserName)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 6) {
                        ForEach(UserProfileManager.avatarPresetColors, id: \.self) { hex in
                            Button {
                                self.newUserColorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hexString: hex))
                                    .frame(width: 13, height: 13)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.primary.opacity(self.newUserColorHex == hex ? 0.5 : 0.1), lineWidth: self.newUserColorHex == hex ? 1.5 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    
                    Toggle("沿用当前 AI 模型配置", isOn: self.$copyCurrentAIConfig)
                        .font(.caption)
                    
                    HStack {
                        Button("取消") {
                            self.resetNewUserDraft()
                        }
                        .controlSize(.small)
                        
                        Spacer()
                        
                        Button("创建并切换") {
                            self.manager.createProfile(
                                displayName: self.newUserName,
                                avatarData: self.newUserAvatarData,
                                avatarColorHex: self.newUserColorHex,
                                copyCurrentAIEndpoints: self.copyCurrentAIConfig,
                                switchImmediately: true
                            )
                            self.resetNewUserDraft()
                            self.editingName = self.manager.activeProfile.displayName
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Button {
                    self.isCreatingUser = true
                    let index = self.manager.profiles.count % UserProfileManager.avatarPresetColors.count
                    self.newUserColorHex = UserProfileManager.avatarPresetColors[index]
                } label: {
                    Label("新建本地用户…", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 318)
        .onAppear {
            self.editingName = self.manager.activeProfile.displayName
        }
        .onChange(of: self.manager.activeProfile.id) { _, _ in
            self.editingName = self.manager.activeProfile.displayName
            self.confirmDeleteUserID = nil
        }
    }
    
    
    @ViewBuilder
    private func userSwitchRow(_ profile: UserProfile, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                guard !isActive else { return }
                self.confirmDeleteUserID = nil
                self.manager.switchToProfile(id: profile.id)
            } label: {
                HStack(spacing: 8) {
                    UserAvatarCircleView(profile: profile, size: 22)
                    Text(profile.displayName)
                        .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer()
                    if isActive {
                        Text("当前")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if self.manager.profiles.count > 1 && !isActive {
                if self.confirmDeleteUserID == profile.id {
                    Button("确认删除", role: .destructive) {
                        self.manager.deleteProfile(id: profile.id)
                        self.confirmDeleteUserID = nil
                    }
                    .controlSize(.mini)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        self.confirmDeleteUserID = profile.id
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("删除此本地用户及数据")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        )
    }
    
    
    private var hasPendingNameChange: Bool {
        
        let trimmed = self.editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != self.manager.activeProfile.displayName
    }
    
    
    private func saveEditedName() {
        
        let trimmed = self.editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.manager.updateProfile(id: self.manager.activeProfile.id, displayName: trimmed)
    }
    
    
    private func resetNewUserDraft() {
        
        self.isCreatingUser = false
        self.newUserName = ""
        self.newUserAvatarData = nil
    }
    
    
    private func pickAvatarForActiveUser() {
        
        self.chooseAvatarData { data in
            self.manager.updateProfile(id: self.manager.activeProfile.id, avatarData: .some(data))
        }
    }
    
    
    private func pickAvatarForNewUser() {
        
        self.chooseAvatarData { data in
            self.newUserAvatarData = data
        }
    }
    
    
    private func chooseAvatarData(_ completion: @escaping @MainActor (Data) -> Void) {
        
        let panel = NSOpenPanel()
        panel.title = "选择头像图片"
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK,
                  let url = panel.url,
                  let image = NSImage(contentsOf: url),
                  let data = UserProfileManager.processedAvatarPNGData(from: image)
            else { return }
            Task { @MainActor in
                completion(data)
            }
        }
    }
}
