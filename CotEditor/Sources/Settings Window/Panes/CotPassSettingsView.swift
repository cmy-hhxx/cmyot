//
//  CotPassSettingsView.swift
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

// MARK: - License & Serial Model (Preserved for Model Compatibility)

nonisolated enum CotPassTier: String, Codable, Sendable, Equatable {
    
    case explorer
    case pro
    case founder
    
    
    var badgeTitle: String {
        switch self {
            case .explorer: "EXPLORER"
            case .pro: "PRO MEMBER"
            case .founder: "FOUNDER"
        }
    }
    
    
    var statusLabel: String {
        switch self {
            case .explorer: "LANDED"
            case .pro: "PRO_ACTIVE"
            case .founder: "FOUNDER"
        }
    }
    
    
    var accessLabel: String {
        switch self {
            case .explorer: "FULL_LOCAL"
            case .pro: "PRO · UNLIMITED"
            case .founder: "LIFETIME · ALL"
        }
    }
    
    
    var summaryLabel: String {
        switch self {
            case .explorer: "免费版 · 1/1 设备"
            case .pro: "Pro 授权已激活"
            case .founder: "Founder 终身版"
        }
    }
}


nonisolated enum CotPassLicense {
    
    /// Validates a CotEditor license key (`COT-PRO-XXXX-XXXX` or `COT-FOUNDER-XXXX-XXXX`).
    static func validate(_ rawKey: String) -> CotPassTier? {
        
        let normalized = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return nil }
        
        if normalized.range(of: #"^COT-FOUNDER-[A-Z0-9]{4}(-[A-Z0-9]{4})?$"#, options: .regularExpression) != nil {
            return .founder
        }
        if normalized.range(of: #"^COT-PRO-[A-Z0-9]{4}-[A-Z0-9]{4}$"#, options: .regularExpression) != nil {
            return .pro
        }
        return nil
    }
    
    
    /// Generates a deterministic-looking readable pass serial code (`XXXX-YYV1`).
    static func generateSerialCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let head = String((0..<4).map { _ in alphabet.randomElement()! })
        let tail = String((0..<2).map { _ in alphabet.randomElement()! })
        return "\(head)-\(tail)V1"
    }
}


// MARK: - Curated Pass Themes & Atelier Finishes

nonisolated struct CotPassTheme: Identifiable, Sendable {
    
    let id: Int
    let title: String
    let subtitle: String
    let matrixColorHex: String
    let accentColorHex: String
    let backgroundTopHex: String
    let backgroundBottomHex: String
    let mascotName: String
    let bitmap: [String]
    
    
    static let allThemes: [CotPassTheme] = [
        CotPassTheme(
            id: 0,
            title: "松烟墨玉",
            subtitle: "PINE_INK_EDITION",
            matrixColorHex: "#44C997",
            accentColorHex: "#E8ECE9",
            backgroundTopHex: "#0E1714",
            backgroundBottomHex: "#15211D",
            mascotName: "松烟",
            bitmap: ["........", "........", "........", "........", "........", "........"]
        ),
        CotPassTheme(
            id: 1,
            title: "鎏金琥珀",
            subtitle: "CHAMPAGNE_GOLD",
            matrixColorHex: "#E5A93C",
            accentColorHex: "#FDE6B8",
            backgroundTopHex: "#16110B",
            backgroundBottomHex: "#241B11",
            mascotName: "鎏金",
            bitmap: ["........", "........", "........", "........", "........", "........"]
        ),
        CotPassTheme(
            id: 2,
            title: "电光紫罗兰",
            subtitle: "ULTRA_VIOLET",
            matrixColorHex: "#715CB2",
            accentColorHex: "#E7E7E7",
            backgroundTopHex: "#0E0E16",
            backgroundBottomHex: "#1A172B",
            mascotName: "紫罗兰",
            bitmap: ["........", "........", "........", "........", "........", "........"]
        ),
        CotPassTheme(
            id: 3,
            title: "信号绯红",
            subtitle: "SIGNAL_CRIMSON",
            matrixColorHex: "#D53740",
            accentColorHex: "#EAEAEA",
            backgroundTopHex: "#111111",
            backgroundBottomHex: "#1D1315",
            mascotName: "绯红",
            bitmap: ["........", "........", "........", "........", "........", "........"]
        ),
        CotPassTheme(
            id: 4,
            title: "抹茶羊皮纸",
            subtitle: "MATCHA_PARCHMENT",
            matrixColorHex: "#5D8718",
            accentColorHex: "#A4CE46",
            backgroundTopHex: "#EFE6CC",
            backgroundBottomHex: "#E7DBB8",
            mascotName: "抹茶",
            bitmap: ["........", "........", "........", "........", "........", "........"]
        ),
        CotPassTheme(
            id: 5,
            title: "宣白朱砂",
            subtitle: "VERMILION_XUAN",
            matrixColorHex: "#D14236",
            accentColorHex: "#1C1F1E",
            backgroundTopHex: "#F6F3EC",
            backgroundBottomHex: "#ECE5D7",
            mascotName: "宣白",
            bitmap: ["........", "........", "........", "........", "........", "........"]
        ),
    ]
    
    
    var isLightSurface: Bool {
        self.id == 4 || self.id == 5
    }
    
    
    static func resolve(index: Int) -> CotPassTheme {
        let safe = ((index % Self.allThemes.count) + Self.allThemes.count) % Self.allThemes.count
        return Self.allThemes[safe]
    }
}


// MARK: - Settings View

struct CotPassSettingsView: View {
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var profileManager = UserProfileManager.shared
    @State private var analytics = AnalyticsManager.shared
    @State private var botStore = AIBotStore.shared
    @State private var styleIndex: Int = 0
    @State private var serialCode: String = ""
    @State private var toastMessage: String?
    
    @State private var tiltX: Double = 0
    @State private var tiltY: Double = 0
    @State private var hoverPoint = UnitPoint(x: 0.5, y: 0.5)
    @State private var isCardHovered = false
    @State private var stampCount: Int = 0
    @State private var isStamping = false
    
    
    private var theme: CotPassTheme {
        CotPassTheme.resolve(index: self.styleIndex)
    }
    
    private var joinedText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: self.profileManager.activeProfile.createdAt)
    }
    
    private var conceptBadge: String {
        let title = self.analytics.personalityProfile?.conceptTitle.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty {
            return title
        }
        let lifetime = self.lifetimeTypedChars
        if lifetime >= 50_000 { return "长卷造物者" }
        if lifetime >= 10_000 { return "恒心执笔人" }
        return "执笔探索者"
    }
    
    private var lifetimeTypedChars: Int {
        var total = self.analytics.todayStats.typedChars
        let todayKey = self.analytics.todayStats.dateKey
        for stat in self.analytics.recentDailyStats where stat.dateKey != todayKey {
            total += stat.typedChars
        }
        return total
    }
    
    private var enabledBotCount: Int {
        AIBotID.allCases.filter { self.botStore.config(for: $0).isEnabled }.count
    }
    
    
    var body: some View {
        let daily14 = self.analytics.dailySeries(days: 14).map { Double($0.typedChars) }
        let streakDays = self.analytics.currentWritingStreak
        let docCount = CotLocalDatabase.shared.documents.count
        
        VStack(alignment: .center, spacing: 20) {
            // Original Horizontal Engraved Atelier Colophon Card
            CotPassCardView(
                theme: self.theme,
                profile: self.profileManager.activeProfile,
                avatarImage: self.profileManager.avatarImage(for: self.profileManager.activeProfile),
                serialCode: self.serialCode,
                joinedText: self.joinedText,
                conceptBadge: self.conceptBadge,
                waveformValues: daily14,
                lifetimeTypedChars: self.lifetimeTypedChars,
                streakDays: streakDays,
                docCount: docCount,
                enabledBotCount: self.enabledBotCount,
                specularPoint: self.hoverPoint,
                isHovered: self.isCardHovered,
                isStamping: self.isStamping,
                onTapChopSeal: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.52)) {
                        self.isStamping = true
                        self.stampCount += 1
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                            self.isStamping = false
                        }
                    }
                    self.showToast(AppLanguage.text("✓ 朱砂藏书印已钤落 (#\(self.stampCount))", en: "✓ Studio Chop Stamped (#\(self.stampCount))"))
                }
            )
            .rotation3DEffect(.degrees(self.tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
            .rotation3DEffect(.degrees(self.tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .scaleEffect(self.isCardHovered ? 1.015 : 1.0)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22), value: self.tiltX)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22), value: self.tiltY)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18), value: self.isCardHovered)
            .onContinuousHover { phase in
                switch phase {
                    case .active(let pt):
                        self.isCardHovered = true
                        let ux = max(0, min(1, pt.x / 396.0))
                        let uy = max(0, min(1, pt.y / 234.0))
                        self.hoverPoint = UnitPoint(x: ux, y: uy)
                        let nx = (ux - 0.5) * 2.0
                        let ny = (uy - 0.5) * 2.0
                        self.tiltY = max(-6.5, min(6.5, nx * 6.0))
                        self.tiltX = max(-6.5, min(6.5, -ny * 5.0))
                    case .ended:
                        self.isCardHovered = false
                        self.tiltX = 0
                        self.tiltY = 0
                        self.hoverPoint = UnitPoint(x: 0.5, y: 0.5)
                }
            }
            
            // Material Finish Selector Card
            VStack(alignment: .leading, spacing: 7) {
                Text("铭牌材质")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 3)
                
                HStack(spacing: 6) {
                    ForEach(CotPassTheme.allThemes) { option in
                        let isSelected = (option.id == self.theme.id)
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                                self.styleIndex = option.id
                            }
                            CotLocalDatabase.shared.set("\(option.id)", forKey: CotLocalDatabase.ConfigKey.cotPassStyleIndex)
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color(hexString: option.matrixColorHex))
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color(hexString: option.backgroundTopHex), lineWidth: 1)
                                    )
                                
                                Text(option.mascotName)
                                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? Color.primary.opacity(self.colorScheme == .dark ? 0.14 : 0.08) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(isSelected ? Color(hexString: option.matrixColorHex).opacity(0.65) : Color.clear, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
                .padding(6)
                .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(self.cardBorder, lineWidth: 1)
                )
            }
            
            // Single Genuine Plain-Text Colophon Copy Action
            HStack(spacing: 12) {
                Button {
                    self.copyPlainColophon()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                        Text(AppLanguage.text("复制手稿落款", en: "Copy Colophon Signature"))
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(self.cardSurface, in: Capsule())
                    .overlay(Capsule().strokeBorder(self.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                if let toastMessage = self.toastMessage {
                    Text(toastMessage)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            self.loadPassState()
        }
    }
    
    
    private var cardSurface: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.055) : Color.white
    }
    
    private var cardBorder: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }
    
    
    private func loadPassState() {
        let db = CotLocalDatabase.shared
        let rawIndex = Int(db.string(forKey: CotLocalDatabase.ConfigKey.cotPassStyleIndex, default: "0")) ?? 0
        self.styleIndex = ((rawIndex % CotPassTheme.allThemes.count) + CotPassTheme.allThemes.count) % CotPassTheme.allThemes.count
        
        let storedSerial = db.string(forKey: CotLocalDatabase.ConfigKey.cotPassSerialCode)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if storedSerial.isEmpty {
            let generated = CotPassLicense.generateSerialCode()
            db.set(generated, forKey: CotLocalDatabase.ConfigKey.cotPassSerialCode)
            self.serialCode = generated
        } else {
            self.serialCode = storedSerial
        }
    }
    
    
    private func copyPlainColophon() {
        let name = self.profileManager.activeProfile.displayName
        let chars = self.lifetimeTypedChars.formatted(.number.grouping(.automatic))
        let streak = self.analytics.currentWritingStreak
        let text = """
        「\(name) · \(self.conceptBadge)」
        累计手写 \(chars) 字 · 连续执笔 \(streak) 天 · 手稿 \(CotLocalDatabase.shared.documents.count) 篇
        COTEDITOR ATELIER · NO. \(self.serialCode) · SINCE \(self.joinedText)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        self.showToast("✓ 已复制纯文本签名")
    }
    
    
    private func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.16)) {
            self.toastMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2.0))
            await MainActor.run {
                if self.toastMessage == message {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.toastMessage = nil
                    }
                }
            }
        }
    }
}


// MARK: - Original Horizontal Atelier Colophon Card

struct CotPassCardView: View {
    
    let theme: CotPassTheme
    let profile: UserProfile
    let avatarImage: NSImage?
    let serialCode: String
    let joinedText: String
    let conceptBadge: String
    let waveformValues: [Double]
    let lifetimeTypedChars: Int
    let streakDays: Int
    let docCount: Int
    let enabledBotCount: Int
    var specularPoint: UnitPoint = UnitPoint(x: 0.5, y: 0.5)
    var isHovered: Bool = false
    var isStamping: Bool = false
    var onTapChopSeal: (() -> Void)? = nil
    
    
    var body: some View {
        let accent = Color(hexString: self.theme.matrixColorHex)
        let secondaryInk = Color(hexString: self.theme.accentColorHex)
        let topBg = Color(hexString: self.theme.backgroundTopHex)
        let bottomBg = Color(hexString: self.theme.backgroundBottomHex)
        let primaryText: Color = self.theme.isLightSurface ? Color(red: 0.10, green: 0.11, blue: 0.10) : Color.white
        let mutedText: Color = self.theme.isLightSurface ? Color.black.opacity(0.52) : Color.white.opacity(0.50)
        let dividerStroke: Color = self.theme.isLightSurface ? Color.black.opacity(0.09) : Color.white.opacity(0.11)
        let badgeInk: Color = (self.theme.id == 4) ? Color(red: 0.08, green: 0.08, blue: 0.08) : (self.theme.isLightSurface ? .white : .black.opacity(0.88))
        let badgeFill: Color = (self.theme.id == 4) ? Color(hexString: self.theme.accentColorHex) : accent
        
        ZStack {
            // Material metallic/paper gradient surface
            LinearGradient(colors: [topBg, bottomBg], startPoint: .topLeading, endPoint: .bottomTrailing)
            
            // Live 14-day keystroke ink-waveform guilloché seal
            InkWaveformSealCanvas(
                values: self.waveformValues,
                accent: accent,
                isLightSurface: self.theme.isLightSurface
            )
            
            // Letterpress inner registration frame & micro corner L-marks
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(dividerStroke, lineWidth: 0.75)
                .padding(8)
                .allowsHitTesting(false)
            
            // Cursor-tracking diagonal specular foil gleam
            RadialGradient(
                colors: [
                    (self.theme.isLightSurface ? Color.white : accent).opacity(self.isHovered ? 0.22 : 0.07),
                    .clear,
                ],
                center: self.specularPoint,
                startRadius: 10,
                endRadius: 240
            )
            .allowsHitTesting(false)
            
            VStack(alignment: .leading, spacing: 0) {
                // Top Engraved Header Seal
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(accent)
                            .frame(width: 6, height: 6)
                        Text(AppLanguage.text("手稿藏书铭牌", en: "COTEDITOR ATELIER"))
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(accent)
                    }
                    
                    Spacer()
                    
                    Text("\(AppLanguage.text("编号", en: "NO.")) \(self.serialCode)  ·  \(self.joinedText)")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(mutedText)
                }
                
                Spacer(minLength: 10)
                
                // Center Identity Row
                HStack(alignment: .center, spacing: 14) {
                    UserAvatarCircleView(profile: self.profile, size: 48, customImage: self.avatarImage)
                        .overlay(
                            Circle()
                                .strokeBorder(accent.opacity(0.80), lineWidth: 1.5)
                        )
                        .shadow(color: accent.opacity(0.28), radius: 8, y: 2)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text(self.profile.displayName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            Text(self.conceptBadge)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(badgeInk)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2.5)
                                .background(badgeFill, in: Capsule())
                            
                            Text(self.theme.title)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(secondaryInk.opacity(0.85))
                        }
                    }
                    
                    Spacer(minLength: 4)
                    
                    // Interactive carved cinnabar studio chop seal ("墨")
                    Button {
                        self.onTapChopSeal?()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(red: 0.78, green: 0.21, blue: 0.18).opacity(0.92))
                                .frame(width: 30, height: 30)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                        .strokeBorder(Color(red: 0.99, green: 0.95, blue: 0.88).opacity(0.55), lineWidth: 0.8)
                                        .padding(2.5)
                                )
                            
                            Text("墨")
                                .font(.system(size: 14, weight: .black, design: .serif))
                                .foregroundStyle(Color(red: 0.99, green: 0.96, blue: 0.90))
                        }
                        .rotationEffect(.degrees(self.isStamping ? -8 : 3))
                        .scaleEffect(self.isStamping ? 0.84 : 1.0)
                        .shadow(color: Color(red: 0.78, green: 0.21, blue: 0.18).opacity(0.35), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(AppLanguage.text("点击钤印藏书印章", en: "Stamp Atelier Seal"))
                }
                
                Spacer(minLength: 12)
                
                // Engraved Hairline Rule
                Rectangle()
                    .fill(dividerStroke)
                    .frame(height: 1)
                    .padding(.bottom, 12)
                
                // Bottom 4 Live Studio Telemetry Counters
                HStack(spacing: 0) {
                    self.metricCell(
                        label: "累计手写",
                        value: Self.compactChars(self.lifetimeTypedChars),
                        primary: primaryText,
                        muted: mutedText
                    )
                    self.metricCell(
                        label: "连续执笔",
                        value: "\(self.streakDays) 天",
                        primary: primaryText,
                        muted: mutedText
                    )
                    self.metricCell(
                        label: "手稿馆藏",
                        value: "\(self.docCount) 篇",
                        primary: primaryText,
                        muted: mutedText
                    )
                    self.metricCell(
                        label: "在线智能体",
                        value: "\(self.enabledBotCount) 席",
                        primary: primaryText,
                        muted: mutedText
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .frame(width: 396, height: 234)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(self.isHovered ? 0.55 : 0.30), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(self.theme.isLightSurface ? 0.14 : 0.30), radius: 18, y: 8)
    }
    
    
    private func metricCell(label: String, value: String, primary: Color, muted: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(muted)
            Text(value)
                .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    
    private static func compactChars(_ count: Int) -> String {
        if count >= 10_000 {
            return String(format: "%.1f万", Double(count) / 10_000.0)
        }
        return "\(count) 字"
    }
}


/// Draws fine guilloché seal rings and a 14-day writing waveform shaped by the user's actual keystrokes.
private struct InkWaveformSealCanvas: View {
    
    let values: [Double]
    let accent: Color
    let isLightSurface: Bool
    
    
    var body: some View {
        Canvas { context, size in
            // 1. Concentric guilloché seal rings anchored to upper-right studio emblem
            let sealCenter = CGPoint(x: size.width - 54, y: 66)
            for idx in 0..<5 {
                let radius = CGFloat(22 + idx * 12)
                let ringRect = CGRect(
                    x: sealCenter.x - radius,
                    y: sealCenter.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.stroke(
                    Path(ellipseIn: ringRect),
                    with: .color(self.accent.opacity(self.isLightSurface ? 0.10 : 0.12 - Double(idx) * 0.015)),
                    lineWidth: 0.8
                )
            }
            
            // 2. Real 14-day keystroke ribbon curve across the middle-right field
            let samples = self.values.isEmpty ? Array(repeating: 0.0, count: 14) : self.values
            let peak = max(120.0, samples.max() ?? 120.0)
            let baselineY = size.height * 0.62
            let startX: CGFloat = size.width * 0.44
            let widthSpan = size.width - startX - 20
            let stepX = widthSpan / CGFloat(max(1, samples.count - 1))
            
            var wavePath = Path()
            var points: [CGPoint] = []
            for (index, val) in samples.enumerated() {
                let norm = max(0.05, min(1.0, val / peak))
                let x = startX + CGFloat(index) * stepX
                let y = baselineY - CGFloat(norm) * 34
                points.append(CGPoint(x: x, y: y))
            }
            
            if let first = points.first {
                wavePath.move(to: first)
                for idx in 1..<points.count {
                    let prev = points[idx - 1]
                    let curr = points[idx]
                    let midX = (prev.x + curr.x) * 0.5
                    wavePath.addCurve(
                        to: curr,
                        control1: CGPoint(x: midX, y: prev.y),
                        control2: CGPoint(x: midX, y: curr.y)
                    )
                }
                context.stroke(
                    wavePath,
                    with: .color(self.accent.opacity(self.isLightSurface ? 0.42 : 0.48)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                
                for (idx, pt) in points.enumerated() {
                    let r: CGFloat = (idx == points.count - 1) ? 2.6 : 1.5
                    let dotRect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                    context.fill(
                        Path(ellipseIn: dotRect),
                        with: .color(self.accent.opacity(idx == points.count - 1 ? 0.90 : 0.45))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
