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


/// Top-right toolbar avatar control that opens the local user profile & quick pin-todo popover.
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
                
                var hue: CGFloat = 0
                var sat: CGFloat = 0
                var bri: CGFloat = 0
                var alpha: CGFloat = 0
                color.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
                
                // Penalize extreme shadows/highlights while retaining warm tint
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
            let shifted = NSColor(hue: (h + 0.12).truncatingRemainder(dividingBy: 1.0),
                                  saturation: min(0.85, max(0.35, s * 1.15)),
                                  brightness: min(0.88, max(0.45, b)),
                                  alpha: 1)
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
        let tuned = NSColor(
            hue: h,
            saturation: min(0.82, max(0.32, s * 1.25)),
            brightness: min(0.84, max(0.38, b)),
            alpha: 1.0
        )
        return Color(nsColor: tuned)
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


// MARK: - Main Profile & Quick Todo Popover

private enum QuickTodoDeadlineOption: String, CaseIterable, Identifiable {
    
    case none
    case min15
    case hour1
    case tonight
    case custom
    
    var id: String { self.rawValue }
    
    var label: String {
        switch self {
            case .none: "无期限"
            case .min15: "15分"
            case .hour1: "1小时"
            case .tonight: "今晚"
            case .custom: "自定义"
        }
    }
}


/// Ambient user hero with AI personality danmaku, playful avatar/name interactions,
/// and ultra-simple quick todo pinning to the top-right corner of the editor.
struct UserProfilePopoverView: View {
    
    var hostWindow: NSWindow?
    var closePopover: () -> Void = {}
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var manager = UserProfileManager.shared
    @State private var analytics = AnalyticsManager.shared
    
    // Avatar & Name Playful State
    @State private var avatarTapCount = 0
    @State private var avatarSquish = false
    @State private var avatarSpinAngle: Double = 0
    @State private var avatarRingScale: CGFloat = 0.8
    @State private var avatarRingOpacity: Double = 0
    @State private var avatarEasterEggText: String?
    @State private var isAvatarDropTargeted = false
    
    @State private var nameWiggleAngle: Double = 0
    @State private var nameEpithet: String?
    @State private var isEditingName = false
    @State private var editingName = ""
    @FocusState private var isNameFieldFocused: Bool
    
    // AI Personality Danmaku State
    @State private var selectedPersonalityTag: UserPersonalityTag?
    @State private var isConceptCardOpen = false
    
    // Quick Pin Todo State
    @State private var todoDraft = ""
    @State private var deadlineOption: QuickTodoDeadlineOption = .none
    @State private var customDeadline = Date().addingTimeInterval(3600)
    @FocusState private var isTodoFieldFocused: Bool
    
    private static let easterEggLines = [
        "✨ 灵感充能 +1%",
        "⚡ 键盘正在预热",
        "🪐 别戳啦，头像都要晕了",
        "☕ 写累了记得喝口水",
        "🏆 解锁连戳小成就",
        "🧠 今日脑洞已就位",
    ]
    
    private static let playEpithets = [
        "Tab 键守护者",
        "键盘侠本侠",
        "深夜赶稿冠军",
        "字数永动机",
        "细节控本人",
        "写完再睡星人",
    ]
    
    
    var body: some View {
        let active = self.manager.activeProfile
        let avatarImage = self.manager.avatarImage(for: active)
        let accentPalette = AvatarColorExtractor.extractPalette(for: active, image: avatarImage)
        
        VStack(alignment: .leading, spacing: 12) {
            self.ambientHeroCard(active: active, avatarImage: avatarImage, palette: accentPalette)
            
            if self.isConceptCardOpen {
                self.personalityConceptCard(palette: accentPalette)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            if self.manager.profiles.count > 1 {
                self.compactAccountSwitcher()
            }
            
            self.quickPinTodoSection()
            
            Divider()
            
            self.footerBar()
        }
        .padding(14)
        .frame(width: 344)
        .onAppear {
            self.editingName = self.manager.activeProfile.displayName
            Task {
                await self.analytics.refreshPersonalityProfile(force: false)
            }
        }
    }
    
    
    // MARK: Apple Music Ambient Hero + Danmaku
    
    @ViewBuilder
    private func ambientHeroCard(
        active: UserProfile,
        avatarImage: NSImage?,
        palette: AvatarColorExtractor.Palette
    ) -> some View {
        let profile = self.analytics.personalityProfile
        let tags = profile?.tags ?? []
        
        ZStack(alignment: .topTrailing) {
            // Apple Music-inspired blurred color wash extracted from avatar
            ZStack {
                LinearGradient(
                    colors: [
                        palette.primary.opacity(self.colorScheme == .dark ? 0.52 : 0.34),
                        palette.secondary.opacity(self.colorScheme == .dark ? 0.38 : 0.24),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                Circle()
                    .fill(palette.primary.opacity(self.colorScheme == .dark ? 0.55 : 0.42))
                    .frame(width: 170, height: 170)
                    .blur(radius: 34)
                    .offset(x: -75, y: -32)
                
                Circle()
                    .fill(palette.secondary.opacity(self.colorScheme == .dark ? 0.48 : 0.36))
                    .frame(width: 150, height: 150)
                    .blur(radius: 30)
                    .offset(x: 90, y: 38)
            }
            .background(.ultraThinMaterial)
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    // Playful clickable avatar (drop or right-click to change photo)
                    Button {
                        self.triggerAvatarFunReaction()
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(Color.white.opacity(self.avatarRingOpacity), lineWidth: 2)
                                .frame(width: 58, height: 58)
                                .scaleEffect(self.avatarRingScale)
                            
                            UserAvatarCircleView(profile: active, size: 52, customImage: avatarImage)
                                .scaleEffect(self.avatarSquish ? 0.84 : 1.0)
                                .rotationEffect(.degrees(self.avatarSpinAngle))
                                .shadow(color: palette.primary.opacity(0.45), radius: 8, y: 3)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            self.isAvatarDropTargeted ? Color.white : Color.white.opacity(0.28),
                                            lineWidth: self.isAvatarDropTargeted ? 2.5 : 1
                                        )
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .help("点一点头像试试看（拖入图片或右键可换头像）")
                    .onDrop(of: [.fileURL, .image], isTargeted: self.$isAvatarDropTargeted) { providers in
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
                        Button("修改昵称") { self.beginNameEdit() }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if self.isEditingName {
                            TextField("你的名字", text: self.$editingName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13.5, weight: .semibold))
                                .focused(self.$isNameFieldFocused)
                                .onSubmit { self.commitNameEdit() }
                                .onExitCommand { self.cancelNameEdit() }
                        } else {
                            Button {
                                self.triggerNameFunReaction()
                            } label: {
                                Text(active.displayName)
                                    .font(.system(size: 15.5, weight: .bold))
                                    .foregroundStyle(self.colorScheme == .dark ? .white : Color(red: 0.11, green: 0.11, blue: 0.12))
                                    .lineLimit(1)
                                    .rotationEffect(.degrees(self.nameWiggleAngle))
                            }
                            .buttonStyle(.plain)
                            .help("点一点昵称换个头衔")
                        }
                        
                        if let egg = self.avatarEasterEggText {
                            Text(egg)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(self.colorScheme == .dark ? .white.opacity(0.92) : .primary)
                                .transition(.opacity)
                        } else if let epithet = self.nameEpithet {
                            Text("「\(epithet)」")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(self.colorScheme == .dark ? .white.opacity(0.90) : .primary)
                                .transition(.opacity)
                        } else {
                            let streak = self.analytics.currentWritingStreak
                            Text(streak > 0
                                 ? "今日 \(self.analytics.todayStats.typedChars.formatted()) 字 · 连续 \(streak) 天"
                                 : "今日手写 \(self.analytics.todayStats.typedChars.formatted()) 字")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(self.colorScheme == .dark ? .white.opacity(0.80) : .secondary)
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                
                // Personality Danmaku Strip (AI analyzes inputs every 6 hours)
                PersonalityDanmakuStrip(
                    tags: tags,
                    selectedTagID: self.selectedPersonalityTag?.id,
                    isAnalyzing: self.analytics.isAnalyzingPersonality,
                    palette: palette,
                    onTapTag: { tag in
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            if self.isConceptCardOpen && self.selectedPersonalityTag?.id == tag.id {
                                self.isConceptCardOpen = false
                                self.selectedPersonalityTag = nil
                            } else {
                                self.selectedPersonalityTag = tag
                                self.isConceptCardOpen = true
                            }
                        }
                    },
                    onTapAnalyzePlaceholder: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            self.isConceptCardOpen = true
                        }
                        Task {
                            await self.analytics.refreshPersonalityProfile(force: true)
                        }
                    }
                )
            }
            .padding(12)
            
            // Subtle overflow actions menu in top-right of hero
            Menu {
                Button("更换头像…") { self.pickAvatarForActiveUser() }
                if avatarImage != nil {
                    Button("恢复默认头像") {
                        self.manager.updateProfile(id: active.id, avatarData: .some(nil))
                    }
                }
                Button("修改昵称") { self.beginNameEdit() }
                Divider()
                Button("查看 / 更新 AI 性格理解") {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        self.isConceptCardOpen = true
                    }
                    Task { await self.analytics.refreshPersonalityProfile(force: true) }
                }
                Button("打开设置与多账户管理…") {
                    self.closePopover()
                    NSApp.sendAction(#selector(AppDelegate.showSettingsWindow(_:)), to: nil, from: nil)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(self.colorScheme == .dark ? .white.opacity(0.85) : .primary.opacity(0.75))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(self.colorScheme == .dark ? 0.16 : 0.08)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.primary.opacity(0.32), lineWidth: 1)
        )
    }
    
    
    // MARK: AI Concept Portrait Expansion Card
    
    @ViewBuilder
    private func personalityConceptCard(palette: AvatarColorExtractor.Palette) -> some View {
        let profile = self.analytics.personalityProfile
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.primary)
                    Text(profile?.conceptTitle ?? "AI 眼中的你")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                
                Spacer()
                
                if self.analytics.isAnalyzingPersonality {
                    ProgressView().controlSize(.mini)
                } else {
                    Button("重新洞察") {
                        Task { await self.analytics.refreshPersonalityProfile(force: true) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.primary)
                }
                
                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) {
                        self.isConceptCardOpen = false
                        self.selectedPersonalityTag = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if let tag = self.selectedPersonalityTag {
                HStack(alignment: .top, spacing: 6) {
                    Text("#\(tag.label)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(palette.primary))
                    
                    Text(tag.explanation)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.primary.opacity(self.colorScheme == .dark ? 0.16 : 0.09))
                )
            }
            
            if let profile {
                Text(profile.conceptSummary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if !profile.writingStyleNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(profile.writingStyleNotes.prefix(3), id: \.self) { note in
                            Text("· \(note)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                HStack {
                    Text("模型：\(profile.modelUsed)")
                    Spacer()
                    Text("更新于 \(profile.generatedAt.formatted(date: .omitted, time: .shortened)) · 每 6 小时自动洞察")
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            } else {
                Text(self.analytics.personalityErrorMessage ?? "后台每隔 6 小时会自动阅读你近期写下的文字，提炼 8 字以内的个性弹幕标签与人物印象。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(self.colorScheme == .dark ? 0.05 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    
    // MARK: Ultra-Simple Account Switcher (when > 1 account exists)
    
    @ViewBuilder
    private func compactAccountSwitcher() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(self.manager.profiles) { profile in
                    let isActive = (profile.id == self.manager.activeProfile.id)
                    Button {
                        if !isActive {
                            self.manager.switchToProfile(id: profile.id)
                            self.editingName = self.manager.activeProfile.displayName
                        }
                    } label: {
                        HStack(spacing: 5) {
                            UserAvatarCircleView(profile: profile, size: 16)
                            Text(profile.displayName)
                                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isActive ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(isActive ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    
    // MARK: Ultra-Simple Quick Pin Todo Composer
    
    @ViewBuilder
    private func quickPinTodoSection() -> some View {
        let pinned = self.analytics.pinnedTodos
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("置顶 Todo", systemImage: "pin.fill")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("设了 DDL 会随时间逼近越来越大")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            
            HStack(spacing: 6) {
                TextField("写一件要紧事，回车 Pin 到右上角…", text: self.$todoDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused(self.$isTodoFieldFocused)
                    .onSubmit {
                        self.submitPinnedTodo()
                    }
                
                Button("Pin") {
                    self.submitPinnedTodo()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(self.todoDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            HStack(spacing: 5) {
                ForEach(QuickTodoDeadlineOption.allCases) { option in
                    let isSelected = (self.deadlineOption == option)
                    Button {
                        withAnimation(.easeOut(duration: 0.14)) {
                            self.deadlineOption = option
                        }
                    } label: {
                        Text(option.label)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if self.deadlineOption == .custom {
                DatePicker("截止", selection: self.$customDeadline, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .font(.system(size: 11))
                    .datePickerStyle(.compact)
            }
            
            if !pinned.isEmpty {
                VStack(spacing: 5) {
                    ForEach(pinned.prefix(4)) { item in
                        HStack(spacing: 7) {
                            Button {
                                self.analytics.toggleReminderCompleted(id: item.id)
                            } label: {
                                Image(systemName: "circle")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("标记完成")
                            
                            Text(item.title)
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            if item.hasDeadline {
                                let remaining = item.dueDate.timeIntervalSince(Date())
                                Text(PinnedTodoUrgency.formatRemaining(remaining))
                                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                                    .foregroundStyle(remaining <= 600 ? Color.red : Color.secondary)
                            }
                            
                            Button {
                                self.analytics.unpinReminder(id: item.id)
                            } label: {
                                Image(systemName: "pin.slash")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("取消置顶")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(self.colorScheme == .dark ? 0.05 : 0.035))
                        )
                    }
                }
            }
        }
    }
    
    
    // MARK: Footer
    
    @ViewBuilder
    private func footerBar() -> some View {
        HStack {
            Button {
                self.closePopover()
                AnalyticsDashboardWindowController.shared.showInWindow(preferredWindow: self.hostWindow)
            } label: {
                Label("打开创作案头", systemImage: "square.grid.2x2")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Spacer()
            
            Button("新建用户 / 设置") {
                self.closePopover()
                NSApp.sendAction(#selector(AppDelegate.showSettingsWindow(_:)), to: nil, from: nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }
    
    
    // MARK: Actions & Playful Animations
    
    private func triggerAvatarFunReaction() {
        
        self.avatarTapCount += 1
        
        withAnimation(.spring(response: 0.22, dampingFraction: 0.42)) {
            self.avatarSquish = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.55)) {
                self.avatarSquish = false
            }
        }
        
        if self.avatarTapCount % 3 == 0 {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.72)) {
                self.avatarSpinAngle += 360
            }
        }
        
        self.avatarRingScale = 0.85
        self.avatarRingOpacity = 0.75
        withAnimation(.easeOut(duration: 0.45)) {
            self.avatarRingScale = 1.45
            self.avatarRingOpacity = 0
        }
        
        let msg = Self.easterEggLines[(self.avatarTapCount - 1) % Self.easterEggLines.count]
        withAnimation(.easeOut(duration: 0.15)) {
            self.nameEpithet = nil
            self.avatarEasterEggText = msg
        }
        let capturedCount = self.avatarTapCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if self.avatarTapCount == capturedCount {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.avatarEasterEggText = nil
                }
            }
        }
    }
    
    
    private func triggerNameFunReaction() {
        
        withAnimation(.spring(response: 0.18, dampingFraction: 0.35)) {
            self.nameWiggleAngle = -4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) {
                self.nameWiggleAngle = 0
            }
        }
        
        let nextEpithet = Self.playEpithets.randomElement() ?? "写作中"
        withAnimation(.easeOut(duration: 0.15)) {
            self.avatarEasterEggText = nil
            self.nameEpithet = nextEpithet
        }
    }
    
    
    private func beginNameEdit() {
        
        self.editingName = self.manager.activeProfile.displayName
        self.isEditingName = true
        self.isNameFieldFocused = true
    }
    
    
    private func commitNameEdit() {
        
        let trimmed = self.editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != self.manager.activeProfile.displayName {
            self.manager.updateProfile(id: self.manager.activeProfile.id, displayName: trimmed)
        } else {
            self.editingName = self.manager.activeProfile.displayName
        }
        self.isEditingName = false
    }
    
    
    private func cancelNameEdit() {
        
        self.editingName = self.manager.activeProfile.displayName
        self.isEditingName = false
    }
    
    
    private func submitPinnedTodo() {
        
        let trimmed = self.todoDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let deadline: Date? = switch self.deadlineOption {
            case .none:
                nil
            case .min15:
                Date().addingTimeInterval(15 * 60)
            case .hour1:
                Date().addingTimeInterval(3600)
            case .tonight:
                Self.tonightDeadline()
            case .custom:
                self.customDeadline
        }
        
        self.analytics.addPinnedTodo(title: trimmed, deadline: deadline)
        self.todoDraft = ""
        self.deadlineOption = .none
    }
    
    
    private static func tonightDeadline(from now: Date = Date()) -> Date {
        
        let cal = Calendar.current
        if let today22 = cal.date(bySettingHour: 22, minute: 0, second: 0, of: now),
           today22.timeIntervalSince(now) > 30 * 60
        {
            return today22
        }
        return now.addingTimeInterval(3 * 3600)
    }
    
    
    private func pickAvatarForActiveUser() {
        
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
                self.manager.updateProfile(id: self.manager.activeProfile.id, avatarData: .some(data))
            }
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
}


// MARK: - Personality Danmaku Strip

private struct DanmakuTrackWidthKey: PreferenceKey {
    
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}


private struct PersonalityDanmakuStrip: View {
    
    let tags: [UserPersonalityTag]
    let selectedTagID: String?
    let isAnalyzing: Bool
    let palette: AvatarColorExtractor.Palette
    let onTapTag: (UserPersonalityTag) -> Void
    let onTapAnalyzePlaceholder: () -> Void
    
    @State private var isHovered = false
    @State private var accumulatedOffset: TimeInterval = 0
    @State private var anchorDate = Date()
    @State private var laneWidths: [Int: CGFloat] = [:]
    @Environment(\.colorScheme) private var colorScheme
    
    
    var body: some View {
        if self.tags.isEmpty {
            Button {
                self.onTapAnalyzePlaceholder()
            } label: {
                HStack(spacing: 5) {
                    if self.isAnalyzing {
                        ProgressView().controlSize(.mini)
                        Text("正在根据近期输入分析性格弹幕…")
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                        Text("每 6 小时自动提炼性格弹幕 · 点此立即生成")
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(self.colorScheme == .dark ? .white.opacity(0.88) : .primary.opacity(0.75))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(self.colorScheme == .dark ? 0.16 : 0.08)))
            }
            .buttonStyle(.plain)
        } else {
            let lane0 = Array(self.tags.enumerated().filter { $0.offset % 2 == 0 }.map(\.element))
            let lane1 = Array(self.tags.enumerated().filter { $0.offset % 2 == 1 }.map(\.element))
            
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                let elapsed = self.isHovered
                    ? self.accumulatedOffset
                    : self.accumulatedOffset + max(0, context.date.timeIntervalSince(self.anchorDate))
                VStack(alignment: .leading, spacing: 5) {
                    self.danmakuLane(laneIndex: 0, tags: lane0, phase: elapsed, speed: 20)
                    if !lane1.isEmpty {
                        self.danmakuLane(laneIndex: 1, tags: lane1, phase: elapsed + 2.4, speed: 15)
                    }
                }
            }
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
    }
    
    
    @ViewBuilder
    private func danmakuLane(laneIndex: Int, tags: [UserPersonalityTag], phase: TimeInterval, speed: CGFloat) -> some View {
        let viewportW: CGFloat = 296
        let measured = self.laneWidths[laneIndex] ?? CGFloat(max(1, tags.count)) * 84
        let unitW = max(20, measured + 10)
        let travel = CGFloat(phase) * speed
        let xOffset = -(travel.truncatingRemainder(dividingBy: unitW))
        
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(tags) { tag in
                    self.danmakuPill(tag: tag)
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: DanmakuTrackWidthKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(DanmakuTrackWidthKey.self) { width in
                if width > 0 {
                    self.laneWidths[laneIndex] = width
                }
            }
            
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 8) {
                    ForEach(tags) { tag in
                        self.danmakuPill(tag: tag)
                    }
                }
            }
        }
        .offset(x: xOffset)
        .frame(width: viewportW, height: 22, alignment: .leading)
        .clipped()
    }
    
    
    @ViewBuilder
    private func danmakuPill(tag: UserPersonalityTag) -> some View {
        let isSelected = (self.selectedTagID == tag.id)
        
        Button {
            self.onTapTag(tag)
        } label: {
            Text(tag.label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isSelected ? .white : (self.colorScheme == .dark ? .white.opacity(0.95) : .primary))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(
                            isSelected
                                ? self.palette.primary
                                : Color.primary.opacity(self.colorScheme == .dark ? 0.22 : 0.10)
                        )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(isSelected ? 0.55 : 0.20), lineWidth: 0.8)
                )
                .fixedSize()
        }
        .buttonStyle(.plain)
        .help("点击查看 AI 理解：\(tag.label)")
    }
}
