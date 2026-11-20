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
                            colors: [baseColor.opacity(0.92), baseColor.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(UserProfileManager.initials(for: self.profile.displayName))
                    .font(.system(size: max(10, self.size * 0.42), weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .frame(width: self.size, height: self.size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
        )
    }
}


private struct UserAvatarToolbarBadgeLabel: View {
    
    @State private var manager = UserProfileManager.shared
    @State private var isHovered = false
    
    
    var body: some View {
        UserAvatarCircleView(profile: self.manager.activeProfile, size: 24)
            .opacity(self.isHovered ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: self.isHovered)
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
        self.toolTip = name
        self.clickButton.toolTip = name
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


/// Clean, centered, soft-rounded popover for managing the active profile and switching local accounts.
struct UserProfilePopoverView: View {
    
    var hostWindow: NSWindow?
    var closePopover: () -> Void = {}
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var manager = UserProfileManager.shared
    @State private var editingName = ""
    @State private var isEditingName = false
    @State private var isAvatarHovered = false
    @State private var isNameHovered = false
    @State private var isDashboardHovered = false
    @State private var isCreateButtonHovered = false
    @State private var isCreatingUser = false
    @State private var newUserName = ""
    @State private var newUserColorHex = UserProfileManager.avatarPresetColors[1]
    @State private var newUserAvatarData: Data?
    @State private var copyCurrentAIConfig = true
    @State private var hoveredProfileID: String?
    @State private var confirmDeleteUserID: String?
    
    
    var body: some View {
        let active = self.manager.activeProfile
        
        VStack(spacing: 12) {
            // Profile
            VStack(spacing: 8) {
                Button {
                    self.pickAvatarForActiveUser()
                } label: {
                    UserAvatarCircleView(profile: active, size: 64)
                        .overlay {
                            Circle()
                                .fill(Color.black.opacity(0.38))
                                .overlay(
                                    Text("更换")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white)
                                )
                                .opacity(self.isAvatarHovered ? 1 : 0)
                        }
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .onHover { hovering in
                    withAnimation(Self.quick) { self.isAvatarHovered = hovering }
                }
                
                // Centered Inline-Editable Name
                if self.isEditingName {
                    HStack(spacing: 6) {
                        TextField("昵称", text: self.$editingName)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(self.surfaceFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(self.strongStroke, lineWidth: 1))
                            .frame(maxWidth: 156)
                            .onSubmit {
                                self.commitNameEdit()
                            }
                        
                        Button("完成") {
                            self.commitNameEdit()
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.primary.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                    .transition(.opacity)
                } else {
                    Button {
                        withAnimation(Self.quick) {
                            self.editingName = active.displayName
                            self.isEditingName = true
                        }
                    } label: {
                        Text(active.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(self.isNameHovered ? self.surfaceFill : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .onHover { hovering in
                        withAnimation(Self.quick) { self.isNameHovered = hovering }
                    }
                    .help("修改昵称")
                }
                
                // Avatar color
                HStack(spacing: 8) {
                    ForEach(UserProfileManager.avatarPresetColors, id: \.self) { hex in
                        let isSelected = (active.avatarColorHex == hex)
                        Button {
                            withAnimation(Self.quick) {
                                self.manager.updateProfile(id: active.id, avatarColorHex: hex)
                            }
                        } label: {
                            Circle()
                                .fill(Color(hexString: hex))
                                .frame(width: 12, height: 12)
                                .padding(3)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(isSelected ? 0.55 : 0), lineWidth: 1.5)
                                )
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
                
                if active.avatarData != nil {
                    Button("移除照片") {
                        withAnimation(Self.quick) {
                            self.manager.updateProfile(id: active.id, avatarData: .some(nil))
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(self.cardStroke, lineWidth: 1)
            )
            
            // Open Analytics Dashboard
            Button {
                let targetWindow = self.hostWindow
                self.closePopover()
                AnalyticsDashboardWindowController.shared.showInWindow(preferredWindow: targetWindow)
            } label: {
                HStack {
                    Text("数据看板")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .offset(x: self.isDashboardHovered ? 2 : 0)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(
                    self.isDashboardHovered ? self.surfaceFill : self.cardSurface,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(self.cardStroke, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { hovering in
                withAnimation(Self.quick) {
                    self.isDashboardHovered = hovering
                }
            }
            
            // Account Switcher List
            if self.manager.profiles.count > 1 {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(self.manager.profiles) { profile in
                            self.userSwitchRow(profile, isActive: profile.id == active.id)
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 136)
                .fixedSize(horizontal: false, vertical: true)
                .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(self.cardStroke, lineWidth: 1)
                )
            }
            
            // Create New Local User
            if self.isCreatingUser {
                self.createUserCard
                    .transition(.opacity)
            } else {
                Button {
                    withAnimation(Self.quick) {
                        self.isCreatingUser = true
                        let index = self.manager.profiles.count % UserProfileManager.avatarPresetColors.count
                        self.newUserColorHex = UserProfileManager.avatarPresetColors[index]
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("新建用户")
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(self.isCreateButtonHovered ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(self.isCreateButtonHovered ? self.surfaceFill : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .onHover { hovering in
                    withAnimation(Self.quick) {
                        self.isCreateButtonHovered = hovering
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 264)
        .onAppear {
            self.editingName = self.manager.activeProfile.displayName
        }
        .onChange(of: self.manager.activeProfile.id) { _, _ in
            self.editingName = self.manager.activeProfile.displayName
            self.isEditingName = false
            self.confirmDeleteUserID = nil
        }
    }
    
    
    private var createUserCard: some View {
        
        VStack(spacing: 12) {
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
                    size: 44,
                    customImage: self.newUserAvatarData.flatMap { NSImage(data: $0) }
                )
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("选择头像")
            
            TextField("昵称", text: self.$newUserName)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(self.surfaceFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            HStack(spacing: 6) {
                ForEach(UserProfileManager.avatarPresetColors, id: \.self) { hex in
                    let selected = (self.newUserColorHex == hex)
                    Button {
                        withAnimation(Self.quick) {
                            self.newUserColorHex = hex
                        }
                    } label: {
                        Circle()
                            .fill(Color(hexString: hex))
                            .frame(width: 12, height: 12)
                            .padding(3)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.55 : 0), lineWidth: 1.5))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Toggle("沿用当前 AI 配置", isOn: self.$copyCurrentAIConfig)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 12))
            
            HStack(spacing: 8) {
                Button {
                    withAnimation(Self.quick) {
                        self.resetNewUserDraft()
                    }
                } label: {
                    Text("取消")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(self.surfaceFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button {
                    withAnimation(Self.quick) {
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
                } label: {
                    Text("创建")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(Color.primary.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .padding(12)
        .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(self.cardStroke, lineWidth: 1)
        )
    }
    
    
    @ViewBuilder
    private func userSwitchRow(_ profile: UserProfile, isActive: Bool) -> some View {
        let isRowHovered = (self.hoveredProfileID == profile.id)
        
        HStack(spacing: 8) {
            Button {
                guard !isActive else { return }
                self.confirmDeleteUserID = nil
                self.manager.switchToProfile(id: profile.id)
            } label: {
                HStack(spacing: 8) {
                    UserAvatarCircleView(profile: profile, size: 22)
                    Text(profile.displayName)
                        .font(.system(size: 12.5, weight: isActive ? .medium : .regular))
                        .foregroundStyle(isActive ? Color.primary : Color.secondary)
                        .lineLimit(1)
                    Spacer()
                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            if self.manager.profiles.count > 1 && !isActive && (isRowHovered || self.confirmDeleteUserID == profile.id) {
                Button(self.confirmDeleteUserID == profile.id ? "确认删除" : "删除") {
                    if self.confirmDeleteUserID == profile.id {
                        self.manager.deleteProfile(id: profile.id)
                        self.confirmDeleteUserID = nil
                    } else {
                        self.confirmDeleteUserID = profile.id
                    }
                }
                .font(.system(size: 11, weight: self.confirmDeleteUserID == profile.id ? .medium : .regular))
                .foregroundStyle(Color.red.opacity(self.confirmDeleteUserID == profile.id ? 1 : 0.8))
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive || isRowHovered ? self.surfaceFill : Color.clear)
        )
        .onHover { hovering in
            withAnimation(Self.quick) {
                if hovering {
                    self.hoveredProfileID = profile.id
                } else if self.hoveredProfileID == profile.id {
                    self.hoveredProfileID = nil
                }
            }
        }
    }
    
    
    // MARK: Visual Tokens
    
    private static let quick = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.14)
    
    
    private var cardSurface: Color {
        
        self.colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.025)
    }
    
    
    private var cardStroke: Color {
        
        self.colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
    }
    
    
    private var strongStroke: Color {
        
        self.colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.2)
    }
    
    
    private var surfaceFill: Color {
        
        self.colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.045)
    }
    
    
    // MARK: Actions
    
    private func commitNameEdit() {
        
        let trimmed = self.editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != self.manager.activeProfile.displayName {
            self.manager.updateProfile(id: self.manager.activeProfile.id, displayName: trimmed)
        } else {
            self.editingName = self.manager.activeProfile.displayName
        }
        withAnimation(Self.quick) {
            self.isEditingName = false
        }
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
