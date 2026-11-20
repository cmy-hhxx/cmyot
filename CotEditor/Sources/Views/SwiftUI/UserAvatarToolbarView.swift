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
                            colors: [baseColor.opacity(0.95), baseColor.opacity(0.70)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(UserProfileManager.initials(for: self.profile.displayName))
                    .font(.system(size: max(10, self.size * 0.42), weight: .bold, design: .rounded))
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
            .scaleEffect(self.isHovered ? 1.08 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.70), value: self.isHovered)
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
        let themeColor = Color(hexString: active.avatarColorHex)
        
        VStack(spacing: 14) {
            // Centered Cute Hero Profile Section
            VStack(spacing: 10) {
                Button {
                    self.pickAvatarForActiveUser()
                } label: {
                    ZStack {
                        Circle()
                            .fill(themeColor.opacity(self.colorScheme == .dark ? 0.16 : 0.11))
                            .frame(width: 78, height: 78)
                        
                        Circle()
                            .strokeBorder(themeColor.opacity(self.isAvatarHovered ? 0.55 : 0.28), lineWidth: 1.8)
                            .frame(width: 74, height: 74)
                        
                        UserAvatarCircleView(profile: active, size: 64)
                            .overlay {
                                if self.isAvatarHovered {
                                    Circle()
                                        .fill(Color.black.opacity(0.42))
                                    Text("换头像")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .scaleEffect(self.isAvatarHovered ? 1.05 : 1.0)
                    .animation(.spring(response: 0.30, dampingFraction: 0.70), value: self.isAvatarHovered)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .onHover { self.isAvatarHovered = $0 }
                
                // Centered Inline-Editable Name
                if self.isEditingName {
                    HStack(spacing: 6) {
                        TextField("昵称", text: self.$editingName)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(self.surfaceFill, in: Capsule())
                            .overlay(Capsule().strokeBorder(themeColor.opacity(0.45), lineWidth: 1.2))
                            .frame(maxWidth: 156)
                            .onSubmit {
                                self.commitNameEdit()
                            }
                        
                        Button("完成") {
                            self.commitNameEdit()
                        }
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(themeColor, in: Capsule())
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                            self.editingName = active.displayName
                            self.isEditingName = true
                        }
                    } label: {
                        Text(active.displayName)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.045), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help("点击修改昵称")
                }
                
                // Centered Cute Theme Color Dots
                HStack(spacing: 8) {
                    ForEach(UserProfileManager.avatarPresetColors, id: \.self) { hex in
                        let isSelected = (active.avatarColorHex == hex)
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                                self.manager.updateProfile(id: active.id, avatarColorHex: hex)
                            }
                        } label: {
                            Circle()
                                .fill(Color(hexString: hex))
                                .frame(width: isSelected ? 17 : 14, height: isSelected ? 17 : 14)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.white, lineWidth: isSelected ? 2 : 0)
                                )
                                .shadow(color: isSelected ? Color(hexString: hex).opacity(0.45) : .clear, radius: 4, y: 1)
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
                .padding(.top, 2)
                
                if active.avatarData != nil {
                    Button("移除照片") {
                        withAnimation(.easeOut(duration: 0.18)) {
                            self.manager.updateProfile(id: active.id, avatarData: .some(nil))
                        }
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(self.cardStroke, lineWidth: 0.75)
            )
            
            // Primary Action Pill: Open Analytics Dashboard
            Button {
                let targetWindow = self.hostWindow
                self.closePopover()
                AnalyticsDashboardWindowController.shared.showInWindow(preferredWindow: targetWindow)
            } label: {
                Text("打开数据看板")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(self.isDashboardHovered ? Color.white : themeColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        self.isDashboardHovered
                            ? themeColor
                            : themeColor.opacity(self.colorScheme == .dark ? 0.16 : 0.12),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(themeColor.opacity(self.isDashboardHovered ? 0.0 : 0.25), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.16)) {
                    self.isDashboardHovered = hovering
                }
            }
            
            // Account Switcher List
            if self.manager.profiles.count > 1 {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(self.manager.profiles) { profile in
                            self.userSwitchRow(profile, isActive: profile.id == active.id)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 136)
                .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(self.cardStroke, lineWidth: 0.75)
                )
            }
            
            // Create New Local User
            if self.isCreatingUser {
                self.createUserCard
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            } else {
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.80)) {
                        self.isCreatingUser = true
                        let index = self.manager.profiles.count % UserProfileManager.avatarPresetColors.count
                        self.newUserColorHex = UserProfileManager.avatarPresetColors[index]
                    }
                } label: {
                    Text("+ 新建用户")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(self.isCreateButtonHovered ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            self.isCreateButtonHovered ? self.surfaceFill.opacity(1.5) : self.cardSurface,
                            in: Capsule()
                        )
                        .overlay(Capsule().strokeBorder(self.cardStroke, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) {
                        self.isCreateButtonHovered = hovering
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 276)
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
        let previewColor = Color(hexString: self.newUserColorHex)
        
        return VStack(spacing: 10) {
            Button {
                self.pickAvatarForNewUser()
            } label: {
                ZStack {
                    Circle()
                        .fill(previewColor.opacity(0.14))
                        .frame(width: 52, height: 52)
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
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            TextField("输入新用户昵称", text: self.$newUserName)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(self.surfaceFill, in: Capsule())
                .overlay(Capsule().strokeBorder(previewColor.opacity(0.35), lineWidth: 1))
            
            HStack(spacing: 7) {
                ForEach(UserProfileManager.avatarPresetColors, id: \.self) { hex in
                    let selected = (self.newUserColorHex == hex)
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
                            self.newUserColorHex = hex
                        }
                    } label: {
                        Circle()
                            .fill(Color(hexString: hex))
                            .frame(width: selected ? 15 : 12, height: selected ? 15 : 12)
                            .overlay(Circle().strokeBorder(.white, lineWidth: selected ? 1.5 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Toggle("沿用 AI 配置", isOn: self.$copyCurrentAIConfig)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
            
            HStack(spacing: 8) {
                Button("取消") {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        self.resetNewUserDraft()
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(self.surfaceFill, in: Capsule())
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button("创建") {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
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
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(previewColor, in: Capsule())
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .padding(12)
        .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(previewColor.opacity(0.28), lineWidth: 0.9)
        )
    }
    
    
    @ViewBuilder
    private func userSwitchRow(_ profile: UserProfile, isActive: Bool) -> some View {
        let isRowHovered = (self.hoveredProfileID == profile.id)
        let accent = Color(hexString: profile.avatarColorHex)
        
        HStack(spacing: 9) {
            Button {
                guard !isActive else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                    self.confirmDeleteUserID = nil
                    self.manager.switchToProfile(id: profile.id)
                }
            } label: {
                HStack(spacing: 9) {
                    UserAvatarCircleView(profile: profile, size: 24)
                    Text(profile.displayName)
                        .font(.system(size: 12.5, weight: isActive ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(isActive ? Color.primary : Color.secondary)
                        .lineLimit(1)
                    Spacer()
                    if isActive {
                        Text("当前")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(accent.opacity(0.14), in: Capsule())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            if self.manager.profiles.count > 1 && !isActive && (isRowHovered || self.confirmDeleteUserID == profile.id) {
                if self.confirmDeleteUserID == profile.id {
                    Button("确认") {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                            self.manager.deleteProfile(id: profile.id)
                            self.confirmDeleteUserID = nil
                        }
                    }
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red, in: Capsule())
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                } else {
                    Button("删除") {
                        withAnimation(.easeOut(duration: 0.15)) {
                            self.confirmDeleteUserID = profile.id
                        }
                    }
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.red.opacity(0.10), in: Capsule())
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isActive
                        ? accent.opacity(self.colorScheme == .dark ? 0.14 : 0.09)
                        : (isRowHovered ? self.surfaceFill : Color.clear)
                )
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                if hovering {
                    self.hoveredProfileID = profile.id
                } else if self.hoveredProfileID == profile.id {
                    self.hoveredProfileID = nil
                }
            }
        }
    }
    
    
    // MARK: Visual Tokens
    
    private var cardSurface: Color {
        
        self.colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
    
    
    private var cardStroke: Color {
        
        self.colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }
    
    
    private var surfaceFill: Color {
        
        self.colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }
    
    
    // MARK: Actions
    
    private func commitNameEdit() {
        
        let trimmed = self.editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != self.manager.activeProfile.displayName {
            self.manager.updateProfile(id: self.manager.activeProfile.id, displayName: trimmed)
        } else {
            self.editingName = self.manager.activeProfile.displayName
        }
        withAnimation(.spring(response: 0.26, dampingFraction: 0.80)) {
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
