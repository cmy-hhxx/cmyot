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
                            colors: [baseColor.opacity(0.92), baseColor.opacity(0.80)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(UserProfileManager.initials(for: self.profile.displayName))
                    .font(.system(size: max(10, self.size * 0.42), weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .frame(width: self.size, height: self.size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
        )
    }
}


private struct UserAvatarToolbarBadgeLabel: View {
    
    @State private var manager = UserProfileManager.shared
    @State private var isHovered = false
    
    
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    Color(red: 0.18, green: 0.56, blue: 0.40).opacity(self.isHovered ? 0.55 : 0),
                    lineWidth: 1.5
                )
                .frame(width: 28, height: 28)
                .scaleEffect(self.isHovered ? 1.08 : 0.94)
            
            UserAvatarCircleView(profile: self.manager.activeProfile, size: 24)
                .scaleEffect(self.isHovered ? 1.07 : 1.0)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: self.isHovered)
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


// MARK: - Apple Music Style Avatar Accent Extractor

@MainActor
private enum AvatarColorExtractor {
    
    struct Palette: Equatable {
        let primary: Color
        let secondary: Color
    }
    
    private static var cache: [String: Palette] = [:]
    
    
    static func extractPalette(for profile: UserProfile, image: NSImage?) -> Palette {
        
        let key = "\(profile.id)|\(profile.avatarData?.count ?? 0)|\(profile.avatarColorHex)"
        if let cached = self.cache[key] {
            return cached
        }
        
        let fallbackPrimary = Color(hexString: profile.avatarColorHex)
        let fallbackSecondary = Self.hueShiftedFallback(from: profile.avatarColorHex)
        let fallback = Palette(primary: fallbackPrimary, secondary: fallbackSecondary)
        
        guard let image,
              let bitmap = Self.downsample24x24(image)
        else {
            self.cache[key] = fallback
            return fallback
        }
        
        struct Bucket {
            var rSum: Double = 0
            var gSum: Double = 0
            var bSum: Double = 0
            var weightSum: Double = 0
        }
        
        var buckets = Array(repeating: Bucket(), count: 12)
        for y in 0..<24 {
            for x in 0..<24 {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.alphaComponent < 0.25 { continue }
                
                var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
                color.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
                
                let lumaWeight: Double = (bri < 0.08 || bri > 0.96) ? 0.15 : 1.0
                let chromaWeight = max(0.08, Double(sat) * 1.8) * lumaWeight
                let idx = min(11, max(0, Int(hue * 12.0)))
                
                buckets[idx].rSum += Double(color.redComponent) * chromaWeight
                buckets[idx].gSum += Double(color.greenComponent) * chromaWeight
                buckets[idx].bSum += Double(color.blueComponent) * chromaWeight
                buckets[idx].weightSum += chromaWeight
            }
        }
        
        let ranked = buckets.enumerated()
            .filter { $0.element.weightSum > 0 }
            .sorted { $0.element.weightSum > $1.element.weightSum }
        
        guard let top = ranked.first else {
            self.cache[key] = fallback
            return fallback
        }
        
        let primaryNS = NSColor(
            srgbRed: top.element.rSum / top.element.weightSum,
            green: top.element.gSum / top.element.weightSum,
            blue: top.element.bSum / top.element.weightSum,
            alpha: 1
        )
        let primary = Self.vibrantAmbientColor(from: primaryNS)
        
        let second = ranked.first { candidate in
            let dist = min(abs(candidate.offset - top.offset), 12 - abs(candidate.offset - top.offset))
            return dist >= 2
        }
        let secondary: Color
        if let second {
            let ns = NSColor(
                srgbRed: second.element.rSum / second.element.weightSum,
                green: second.element.gSum / second.element.weightSum,
                blue: second.element.bSum / second.element.weightSum,
                alpha: 1
            )
            secondary = Self.vibrantAmbientColor(from: ns)
        } else {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            primaryNS.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            let shifted = NSColor(
                hue: (h + 0.12).truncatingRemainder(dividingBy: 1.0),
                saturation: min(0.85, max(0.35, s * 1.15)),
                brightness: min(0.88, max(0.45, b)),
                alpha: 1
            )
            secondary = Color(nsColor: shifted)
        }
        
        let palette = Palette(primary: primary, secondary: secondary)
        self.cache[key] = palette
        return palette
    }
    
    
    private static func downsample24x24(_ image: NSImage) -> NSBitmapImageRep? {
        
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 24,
            pixelsHigh: 24,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        
        rep.size = NSSize(width: 24, height: 24)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 24, height: 24), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
    
    
    private static func vibrantAmbientColor(from color: NSColor) -> Color {
        
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let srgb = color.usingColorSpace(.sRGB) ?? color
        srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(nsColor: NSColor(
            hue: h,
            saturation: min(0.82, max(0.32, s * 1.25)),
            brightness: min(0.84, max(0.38, b)),
            alpha: 1.0
        ))
    }
    
    
    private static func hueShiftedFallback(from hex: String) -> Color {
        
        let base = NSColor(Color(hexString: hex)).usingColorSpace(.sRGB) ?? .systemBlue
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(nsColor: NSColor(
            hue: (h + 0.14).truncatingRemainder(dividingBy: 1.0),
            saturation: min(0.85, max(0.40, s)),
            brightness: min(0.86, max(0.45, b)),
            alpha: 1.0
        ))
    }
}


private enum QuickTodoDDL: String, CaseIterable, Identifiable {
    
    case none = "无期限"
    case min15 = "15分"
    case hour1 = "1小时"
    case tonight = "今晚"
    
    var id: String { self.rawValue }
}


/// Playful, soft-rounded popover for managing the active profile, AI danmaku, and quick pinned todos.
struct UserProfilePopoverView: View {
    
    var hostWindow: NSWindow?
    var closePopover: () -> Void = {}
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var manager = UserProfileManager.shared
    @State private var analytics = AnalyticsManager.shared
    @State private var editingName = ""
    @State private var isEditingName = false
    @State private var didJustSaveName = false
    @State private var isAvatarHovered = false
    @State private var isAvatarDropTargeted = false
    @State private var isNameHovered = false
    @State private var isDashboardHovered = false
    @State private var greeting = Self.nextRandomGreeting()
    @State private var isCreateButtonHovered = false
    @State private var isCreatingTodo = false
    @State private var todoTitle = ""
    @State private var todoDDL: QuickTodoDDL = .none
    @State private var hoveredProfileID: String?
    @State private var confirmDeleteUserID: String?
    @State private var isDotBreathing = false
    
    // Fun click state
    @State private var avatarTapCount = 0
    @State private var avatarSquish = false
    @State private var avatarSpinAngle: Double = 0
    @State private var avatarPulseScale: CGFloat = 0.85
    @State private var avatarPulseOpacity: Double = 0
    @State private var nameWiggleAngle: Double = 0
    @State private var selectedTag: UserPersonalityTag?
    
    @FocusState private var isNameFieldFocused: Bool
    @FocusState private var isTodoFieldFocused: Bool
    @Namespace private var activeSwitchNamespace
    
    
    var body: some View {
        let active = self.manager.activeProfile
        let avatarImage = self.manager.avatarImage(for: active)
        let ambient = AvatarColorExtractor.extractPalette(for: active, image: avatarImage)
        let recent5 = self.analytics.dailySeries(days: 5).map { Double($0.typedChars) }
        let todayChars = self.analytics.todayStats.typedChars
        let tags = self.analytics.personalityProfile?.tags ?? []
        let pinned = self.analytics.pinnedTodos
        
        VStack(spacing: 10) {
            // Active Profile Card with Apple Music Ambient Wash
            VStack(spacing: 10) {
                // Playful rotating greeting + live today pulse pill
                HStack(spacing: 6) {
                    Text(self.greeting)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .onTapGesture {
                            withAnimation(Self.quick) {
                                self.greeting = Self.nextRandomGreeting()
                            }
                        }
                    
                    Spacer()
                    
                    HStack(spacing: 5) {
                        Circle()
                            .fill(self.mintAccent)
                            .frame(width: 5.5, height: 5.5)
                            .scaleEffect(self.isDotBreathing ? 1.25 : 0.85)
                            .opacity(self.isDotBreathing ? 1.0 : 0.55)
                        
                        Text(todayChars > 0 ? "\(todayChars.formatted(.number.grouping(.automatic))) 字" : "准备开写")
                            .font(.system(size: 10.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(self.mintAccent)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(self.mintSoftBg, in: Capsule())
                }
                
                // Tactile Avatar (fun click reaction; drop or right-click to change avatar)
                ZStack {
                    if !tags.isEmpty {
                        CompactDanmakuBackdrop(
                            tags: tags,
                            selectedTagID: self.selectedTag?.id,
                            accent: ambient.primary
                        ) { tapped in
                            withAnimation(Self.spring) {
                                self.selectedTag = (self.selectedTag?.id == tapped.id) ? nil : tapped
                            }
                        }
                    }
                    
                    Button {
                        self.triggerAvatarFunTap()
                    } label: {
                        ZStack(alignment: .bottom) {
                            Circle()
                                .strokeBorder(ambient.primary.opacity(self.avatarPulseOpacity), lineWidth: 2)
                                .frame(width: 74, height: 74)
                                .scaleEffect(self.avatarPulseScale)
                            
                            UserAvatarCircleView(profile: active, size: 68, customImage: avatarImage)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            ambient.primary.opacity(self.isAvatarDropTargeted ? 0.9 : (self.isAvatarHovered ? 0.45 : 0.18)),
                                            lineWidth: self.isAvatarDropTargeted ? 2.5 : 1.5
                                        )
                                )
                                .scaleEffect(self.avatarSquish ? 0.86 : (self.isAvatarDropTargeted ? 1.08 : (self.isAvatarHovered ? 1.03 : 1.0)))
                                .rotationEffect(.degrees(self.avatarSpinAngle))
                                .shadow(
                                    color: ambient.primary.opacity(0.32),
                                    radius: 12,
                                    y: 4
                                )
                            
                            if self.isAvatarDropTargeted {
                                Text("松手换头像")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2.5)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .background(Color.black.opacity(0.45), in: Capsule())
                                    .offset(y: 4)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .onHover { hovering in
                        withAnimation(Self.spring) { self.isAvatarHovered = hovering }
                    }
                    .onDrop(of: [.image, .fileURL], isTargeted: self.$isAvatarDropTargeted) { providers in
                        self.handleAvatarDrop(providers: providers)
                    }
                    .contextMenu {
                        Button("更换头像…") { self.pickAvatarForActiveUser() }
                        if avatarImage != nil {
                            Button("恢复默认头像") {
                                self.manager.updateProfile(id: active.id, avatarData: .some(nil))
                            }
                        }
                        Divider()
                        Button("修改昵称") {
                            withAnimation(Self.spring) {
                                self.editingName = active.displayName
                                self.isEditingName = true
                            }
                        }
                    }
                }
                
                // Centered Fun-Clickable / Editable Name
                if self.isEditingName {
                    HStack(spacing: 6) {
                        TextField("昵称", text: self.$editingName)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 14, weight: .medium))
                            .focused(self.$isNameFieldFocused)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(self.surfaceFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(self.mintAccent.opacity(0.65), lineWidth: 1.25))
                            .frame(maxWidth: 158)
                            .onSubmit {
                                self.commitNameEdit()
                            }
                            .onExitCommand {
                                self.cancelNameEdit()
                            }
                            .onAppear {
                                DispatchQueue.main.async {
                                    self.isNameFieldFocused = true
                                }
                            }
                            .onChange(of: self.isNameFieldFocused) { _, focused in
                                if !focused && self.isEditingName {
                                    self.commitNameEdit()
                                }
                            }
                        
                        Button("完成") {
                            self.commitNameEdit()
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(self.mintAccent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    HStack(spacing: 4) {
                        Button {
                            self.triggerNameFunTap()
                        } label: {
                            HStack(spacing: 5) {
                                Text(active.displayName)
                                    .font(.system(size: 15.5, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .rotationEffect(.degrees(self.nameWiggleAngle))
                                
                                if self.didJustSaveName {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(self.mintAccent)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(self.isNameHovered ? self.surfaceFill : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .contextMenu {
                            Button("修改昵称") {
                                withAnimation(Self.spring) {
                                    self.editingName = active.displayName
                                    self.isEditingName = true
                                }
                            }
                            Button("更换头像…") { self.pickAvatarForActiveUser() }
                        }
                        
                        if self.isNameHovered {
                            Button {
                                withAnimation(Self.spring) {
                                    self.editingName = active.displayName
                                    self.isEditingName = true
                                }
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, height: 22)
                                    .background(self.surfaceFill, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            .transition(.opacity)
                        }
                    }
                    .onHover { hovering in
                        withAnimation(Self.quick) { self.isNameHovered = hovering }
                    }
                }
                
                if let tag = self.selectedTag {
                    HStack(spacing: 6) {
                        Text(tag.explanation.isEmpty ? (self.analytics.personalityProfile?.conceptSummary ?? tag.label) : tag.explanation)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(self.surfaceFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onTapGesture {
                        withAnimation(Self.quick) { self.selectedTag = nil }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .padding(.horizontal, 12)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(self.cardSurface)
                    
                    LinearGradient(
                        colors: [
                            ambient.primary.opacity(self.colorScheme == .dark ? 0.34 : 0.22),
                            ambient.secondary.opacity(self.colorScheme == .dark ? 0.20 : 0.12),
                            .clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blur(radius: 14)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(ambient.primary.opacity(0.24), lineWidth: 1)
            )
            
            // Inviting Dashboard Launch Card with Mini Pixel Sparkbar (no small subtext)
            Button {
                let targetWindow = self.hostWindow
                self.closePopover()
                AnalyticsDashboardWindowController.shared.showInWindow(preferredWindow: targetWindow)
            } label: {
                HStack(spacing: 10) {
                    MiniPopoverSparkMatrix(values: recent5, accent: self.mintAccent, emptyColor: self.surfaceFill)
                        .frame(width: 30, height: 22)
                        .padding(6)
                        .background(self.mintSoftBg, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    
                    Text("数据看板")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Circle()
                        .fill(self.isDashboardHovered ? self.mintAccent : self.surfaceFill)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(self.isDashboardHovered ? Color(nsColor: .windowBackgroundColor) : .secondary)
                                .offset(x: self.isDashboardHovered ? 0.5 : 0, y: self.isDashboardHovered ? -0.5 : 0)
                        )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    self.isDashboardHovered ? self.surfaceFill : self.cardSurface,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(self.isDashboardHovered ? self.mintAccent.opacity(0.35) : self.cardStroke, lineWidth: 1)
                )
                .scaleEffect(self.isDashboardHovered ? 1.01 : 1.0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { hovering in
                withAnimation(Self.spring) {
                    self.isDashboardHovered = hovering
                }
            }
            
            // Fluid Account Switcher List
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
                .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(self.cardStroke, lineWidth: 1)
                )
            }
            
            // Active Pinned Todos List
            if !pinned.isEmpty {
                VStack(spacing: 4) {
                    ForEach(pinned.prefix(3)) { item in
                        HStack(spacing: 7) {
                            Button {
                                self.analytics.toggleReminderCompleted(id: item.id)
                            } label: {
                                Image(systemName: "circle")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(self.mintAccent)
                            }
                            .buttonStyle(.plain)
                            
                            Text(item.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            
                            Spacer(minLength: 4)
                            
                            Button {
                                self.analytics.unpinReminder(id: item.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(self.cardStroke, lineWidth: 1)
                        )
                    }
                }
            }
            
            // Quick Pin Todo Drawer (Replaces Create Local User, which moved to Settings)
            if self.isCreatingTodo {
                self.createTodoCard
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            } else {
                Button {
                    withAnimation(Self.spring) {
                        self.isCreatingTodo = true
                        DispatchQueue.main.async {
                            self.isTodoFieldFocused = true
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("新建置顶 Todo")
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(self.isCreateButtonHovered ? self.mintAccent : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(self.isCreateButtonHovered ? self.mintSoftBg : Color.clear)
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
        .frame(width: 272)
        .onAppear {
            self.editingName = self.manager.activeProfile.displayName
            self.greeting = Self.nextRandomGreeting()
            if !AnimationConstants.isReducedMotionEnabled {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    self.isDotBreathing = true
                }
            } else {
                self.isDotBreathing = true
            }
            Task {
                await self.analytics.refreshPersonalityProfile(force: false)
            }
        }
        .onChange(of: self.manager.activeProfile.id) { _, _ in
            self.editingName = self.manager.activeProfile.displayName
            self.isEditingName = false
            self.confirmDeleteUserID = nil
            self.selectedTag = nil
        }
    }
    
    
    private var createTodoCard: some View {
        
        VStack(spacing: 9) {
            TextField("输入 Todo，回车置顶", text: self.$todoTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(self.$isTodoFieldFocused)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(self.surfaceFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onSubmit {
                    self.submitTodo()
                }
            
            HStack(spacing: 5) {
                ForEach(QuickTodoDDL.allCases) { option in
                    let isSelected = (self.todoDDL == option)
                    Button {
                        withAnimation(Self.quick) {
                            self.todoDDL = option
                        }
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color(nsColor: .windowBackgroundColor) : .secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelected ? self.mintAccent : self.surfaceFill)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            
            HStack(spacing: 8) {
                Button {
                    withAnimation(Self.spring) {
                        self.resetTodoDraft()
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
                    self.submitTodo()
                } label: {
                    Text("置顶")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(self.mintAccent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .padding(10)
        .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
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
                withAnimation(Self.spring) {
                    self.manager.switchToProfile(id: profile.id)
                }
            } label: {
                HStack(spacing: 8) {
                    UserAvatarCircleView(profile: profile, size: 22)
                    Text(profile.displayName)
                        .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Color.primary : Color.secondary)
                        .lineLimit(1)
                    Spacer()
                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(self.mintAccent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            if self.manager.profiles.count > 1 && !isActive && (isRowHovered || self.confirmDeleteUserID == profile.id) {
                let isConfirming = (self.confirmDeleteUserID == profile.id)
                Button(isConfirming ? "确认删除" : "删除") {
                    withAnimation(Self.spring) {
                        if isConfirming {
                            self.manager.deleteProfile(id: profile.id)
                            self.confirmDeleteUserID = nil
                        } else {
                            self.confirmDeleteUserID = profile.id
                        }
                    }
                }
                .font(.system(size: 10.5, weight: isConfirming ? .semibold : .medium))
                .foregroundStyle(isConfirming ? Color.white : Color.red)
                .padding(.horizontal, isConfirming ? 8 : 6)
                .padding(.vertical, 2.5)
                .background(
                    Capsule().fill(isConfirming ? Color.red : Color.red.opacity(0.10))
                )
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(self.surfaceFill)
                    .matchedGeometryEffect(id: "activeProfilePill", in: self.activeSwitchNamespace)
            } else if isRowHovered {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(self.surfaceFill.opacity(0.65))
            }
        }
        .onHover { hovering in
            withAnimation(Self.quick) {
                if hovering {
                    self.hoveredProfileID = profile.id
                } else if self.hoveredProfileID == profile.id {
                    self.hoveredProfileID = nil
                    if self.confirmDeleteUserID == profile.id {
                        self.confirmDeleteUserID = nil
                    }
                }
            }
        }
    }
    
    
    // MARK: Visual Tokens
    
    private static let quick = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.14)
    private static let spring = Animation.spring(response: 0.30, dampingFraction: 0.80)
    
    private var mintAccent: Color {
        self.colorScheme == .dark
            ? Color(red: 0.25, green: 0.84, blue: 0.62)
            : Color(red: 0.16, green: 0.54, blue: 0.38)
    }
    
    private var mintSoftBg: Color {
        self.mintAccent.opacity(self.colorScheme == .dark ? 0.18 : 0.12)
    }
    
    private var cardSurface: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.025)
    }
    
    private var cardStroke: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.065)
    }
    
    private var surfaceFill: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.045)
    }
    
    
    // MARK: Actions
    
    private static var lastGreetingIndex: Int?
    
    private static let randomGreetings: [String] = [
        "灵感已上线",
        "键盘热好了",
        "先写第一行",
        "草稿不怕丑",
        "敲字胜发呆",
        "状态正加载",
        "大脑营业中",
        "别卡在标题",
        "手感在升温",
        "思路已就位",
        "摸会鱼再写",
        "写完这句歇",
    ]
    
    private static func nextRandomGreeting() -> String {
        
        var candidates = Array(Self.randomGreetings.indices)
        if let last = Self.lastGreetingIndex, candidates.count > 1 {
            candidates.removeAll { $0 == last }
        }
        let picked = candidates.randomElement() ?? 0
        Self.lastGreetingIndex = picked
        return Self.randomGreetings[picked]
    }
    
    
    private func commitNameEdit() {
        
        let trimmed = self.editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = !trimmed.isEmpty && trimmed != self.manager.activeProfile.displayName
        if changed {
            self.manager.updateProfile(id: self.manager.activeProfile.id, displayName: trimmed)
        } else {
            self.editingName = self.manager.activeProfile.displayName
        }
        withAnimation(Self.spring) {
            self.isEditingName = false
            if changed {
                self.didJustSaveName = true
            }
        }
        if changed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(Self.quick) {
                    self.didJustSaveName = false
                }
            }
        }
    }
    
    
    private func cancelNameEdit() {
        
        self.editingName = self.manager.activeProfile.displayName
        withAnimation(Self.spring) {
            self.isEditingName = false
        }
    }
    
    
    private func triggerAvatarFunTap() {
        
        self.avatarTapCount += 1
        withAnimation(Self.quick) {
            self.greeting = Self.nextRandomGreeting()
        }
        withAnimation(.spring(response: 0.20, dampingFraction: 0.42)) {
            self.avatarSquish = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.56)) {
                self.avatarSquish = false
            }
        }
        if self.avatarTapCount % 3 == 0 {
            withAnimation(.spring(response: 0.50, dampingFraction: 0.72)) {
                self.avatarSpinAngle += 360
            }
        }
        self.avatarPulseScale = 0.88
        self.avatarPulseOpacity = 0.75
        withAnimation(.easeOut(duration: 0.42)) {
            self.avatarPulseScale = 1.42
            self.avatarPulseOpacity = 0
        }
    }
    
    
    private func triggerNameFunTap() {
        
        withAnimation(Self.quick) {
            self.greeting = Self.nextRandomGreeting()
        }
        withAnimation(.spring(response: 0.16, dampingFraction: 0.35)) {
            self.nameWiggleAngle = -4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.48)) {
                self.nameWiggleAngle = 0
            }
        }
    }
    
    
    private func submitTodo() {
        
        let trimmed = self.todoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        let deadline: Date? = switch self.todoDDL {
            case .none: nil
            case .min15: now.addingTimeInterval(15 * 60)
            case .hour1: now.addingTimeInterval(3600)
            case .tonight:
                Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: now).flatMap {
                    $0.timeIntervalSince(now) > 1800 ? $0 : now.addingTimeInterval(3 * 3600)
                } ?? now.addingTimeInterval(3 * 3600)
        }
        withAnimation(Self.spring) {
            self.analytics.addPinnedTodo(title: trimmed, deadline: deadline)
            self.resetTodoDraft()
        }
    }
    
    
    private func resetTodoDraft() {
        
        self.isCreatingTodo = false
        self.todoTitle = ""
        self.todoDDL = .none
    }
    
    
    private func pickAvatarForActiveUser() {
        
        self.chooseAvatarData { data in
            self.manager.updateProfile(id: self.manager.activeProfile.id, avatarData: .some(data))
        }
    }
    
    
    private func handleAvatarDrop(providers: [NSItemProvider]) -> Bool {
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL? = if let data = item as? Data {
                        URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        item as? URL
                    }
                    guard let url,
                          let image = NSImage(contentsOf: url),
                          let png = UserProfileManager.processedAvatarPNGData(from: image)
                    else { return }
                    Task { @MainActor in
                        self.manager.updateProfile(id: self.manager.activeProfile.id, avatarData: .some(png))
                    }
                }
                return true
            }
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage,
                          let png = UserProfileManager.processedAvatarPNGData(from: image)
                    else { return }
                    Task { @MainActor in
                        self.manager.updateProfile(id: self.manager.activeProfile.id, avatarData: .some(png))
                    }
                }
                return true
            }
        }
        return false
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


private struct MiniPopoverSparkMatrix: View {
    
    let values: [Double]
    let accent: Color
    let emptyColor: Color
    
    
    var body: some View {
        
        Canvas { context, size in
            let cols = max(1, self.values.count)
            let rows = 4
            let gap: CGFloat = 1.8
            let side = max(2.2, min((size.width - gap * CGFloat(cols - 1)) / CGFloat(cols), (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)))
            let peak = max(1.0, self.values.max() ?? 1.0)
            
            for col in 0..<cols {
                let val = self.values[col]
                let active = val > 0 ? max(1, Int((val / peak * Double(rows)).rounded(.up))) : 0
                for row in 0..<rows {
                    let yIdx = rows - 1 - row
                    let rect = CGRect(
                        x: CGFloat(col) * (side + gap),
                        y: CGFloat(yIdx) * (side + gap),
                        width: side,
                        height: side
                    )
                    let color = row < active ? self.accent.opacity(0.45 + 0.55 * Double(row + 1) / Double(rows)) : self.emptyColor
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.2, style: .continuous), with: .color(color))
                }
            }
        }
    }
}


private struct CompactDanmakuBackdrop: View {
    
    let tags: [UserPersonalityTag]
    let selectedTagID: String?
    let accent: Color
    let onTap: (UserPersonalityTag) -> Void
    
    @State private var isHovered = false
    @State private var accumulatedOffset: TimeInterval = 0
    @State private var anchorDate = Date()
    @Environment(\.colorScheme) private var colorScheme
    
    
    var body: some View {
        let topTags = Array(self.tags.enumerated().filter { $0.offset % 2 == 0 }.map(\.element))
        let bottomTags = Array(self.tags.enumerated().filter { $0.offset % 2 == 1 }.map(\.element))
        
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let elapsed = self.isHovered
                ? self.accumulatedOffset
                : self.accumulatedOffset + max(0, context.date.timeIntervalSince(self.anchorDate))
            VStack(spacing: 14) {
                self.lane(tags: topTags, phase: elapsed, speed: 15)
                if !bottomTags.isEmpty {
                    self.lane(tags: bottomTags, phase: elapsed + 2.2, speed: 11)
                }
            }
        }
        .frame(width: 224, height: 64)
        .clipped()
        .onHover { hovering in
            guard hovering != self.isHovered else { return }
            if hovering {
                self.accumulatedOffset += max(0, Date().timeIntervalSince(self.anchorDate))
            } else {
                self.anchorDate = Date()
            }
            self.isHovered = hovering
        }
    }
    
    
    @ViewBuilder
    private func lane(tags: [UserPersonalityTag], phase: TimeInterval, speed: CGFloat) -> some View {
        let cycleW = max(160, CGFloat(max(1, tags.count)) * 78)
        let xOffset = -((CGFloat(phase) * speed).truncatingRemainder(dividingBy: cycleW))
        
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 8) {
                    ForEach(tags) { tag in
                        let isSelected = (self.selectedTagID == tag.id)
                        Button {
                            self.onTap(tag)
                        } label: {
                            Text(tag.label)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : .primary.opacity(0.78))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? self.accent : Color.primary.opacity(self.colorScheme == .dark ? 0.14 : 0.07))
                                )
                                .fixedSize()
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
            }
        }
        .offset(x: xOffset)
        .frame(width: 224, height: 18, alignment: .leading)
    }
}
