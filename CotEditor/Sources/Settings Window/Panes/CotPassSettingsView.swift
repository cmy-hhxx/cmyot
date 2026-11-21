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
import UniformTypeIdentifiers

// MARK: - License & Serial Model

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
    
    
    /// Generates a deterministic-looking readable pass serial code (`COT-XXXX-V1`).
    static func generateSerialCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let head = String((0..<4).map { _ in alphabet.randomElement()! })
        let tail = String((0..<2).map { _ in alphabet.randomElement()! })
        return "\(head)-\(tail)V1"
    }
}


// MARK: - Curated ASCII Pass Themes

nonisolated struct CotPassTheme: Identifiable, Sendable {
    
    let id: Int
    let title: String
    let subtitle: String
    let matrixColorHex: String
    let accentColorHex: String
    let backgroundTopHex: String
    let backgroundBottomHex: String
    let mascotName: String
    /// 8 columns × 6 rows pixel art bitmap (`#` = lit pixel, `.` = empty).
    let bitmap: [String]
    
    
    static let allThemes: [CotPassTheme] = [
        CotPassTheme(
            id: 0,
            title: "EXPLORER",
            subtitle: "BOARDING_PASS",
            matrixColorHex: "#44C997",
            accentColorHex: "#F18D80",
            backgroundTopHex: "#0C1513",
            backgroundBottomHex: "#111313",
            mascotName: "Pixel Hopper",
            bitmap: [
                "..#..#..",
                ".######.",
                "##.##.##",
                "########",
                ".#.##.#.",
                "#......#",
            ]
        ),
        CotPassTheme(
            id: 1,
            title: "ARCHITECT",
            subtitle: "SYSTEM_PASS",
            matrixColorHex: "#38BDF8",
            accentColorHex: "#FBBF24",
            backgroundTopHex: "#0B131E",
            backgroundBottomHex: "#101218",
            mascotName: "Fountain Nib",
            bitmap: [
                "...##...",
                "..####..",
                ".######.",
                ".##..##.",
                "..####..",
                "...##...",
            ]
        ),
        CotPassTheme(
            id: 2,
            title: "CRAFTSMAN",
            subtitle: "STUDIO_PASS",
            matrixColorHex: "#A78BFA",
            accentColorHex: "#34D399",
            backgroundTopHex: "#131021",
            backgroundBottomHex: "#121117",
            mascotName: "Terminal Spark",
            bitmap: [
                "...##...",
                ".#.###..",
                "########",
                "########",
                ".#.###..",
                "...##...",
            ]
        ),
        CotPassTheme(
            id: 3,
            title: "CHRONICLER",
            subtitle: "ARCHIVAL_PASS",
            matrixColorHex: "#F59E0B",
            accentColorHex: "#FB7185",
            backgroundTopHex: "#19130A",
            backgroundBottomHex: "#141210",
            mascotName: "Paper Crown",
            bitmap: [
                "#..##..#",
                "#.####.#",
                "########",
                "########",
                ".######.",
                "........",
            ]
        ),
        CotPassTheme(
            id: 4,
            title: "OPERATOR",
            subtitle: "TERMINAL_PASS",
            matrixColorHex: "#10B981",
            accentColorHex: "#E2E8F0",
            backgroundTopHex: "#0A1410",
            backgroundBottomHex: "#0F1211",
            mascotName: "Signal Core",
            bitmap: [
                ".######.",
                "#......#",
                "#..##..#",
                "#..##..#",
                "#......#",
                ".######.",
            ]
        ),
    ]
    
    
    static func resolve(index: Int) -> CotPassTheme {
        let safe = ((index % Self.allThemes.count) + Self.allThemes.count) % Self.allThemes.count
        return Self.allThemes[safe]
    }
    
    
    /// Renders a clean plaintext ASCII art representation of the Pass for clipboard sharing.
    func asciiRepresentation(serialCode: String, holderName: String, joinedDate: String, tier: CotPassTier) -> String {
        
        let headerTitle = tier == .explorer ? self.title : tier.badgeTitle
        return """
        +----------------------------------------+
        | COTEDITOR                 \(serialCode.padding(toLength: 12, withPad: " ", startingAt: 0)) |
        |   · · + + + · ·   ··  + + · ·   · +    |
        |  · + + [\(self.mascotName)] + + ·       |
        |   · · + + · · ·   + + + · · ·   · +    |
        +----------------------------------------+
        | \(headerTitle)
        | \(self.subtitle)
        |
        | STATUS  > [ \(tier.statusLabel) ]
        | HOLDER  > \(holderName)
        | JOINED  > \(joinedDate)
        | ACCESS  > \(tier.accessLabel)
        | ...................................... |
        | COTEDITOR ▪ V1          WELCOME ABOARD |
        +----------------------------------------+
        """
    }
}


// MARK: - Settings View

struct CotPassSettingsView: View {
    
    var onRequestMigrationExport: () -> Void = {}
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var profileManager = UserProfileManager.shared
    @State private var styleIndex: Int = 0
    @State private var serialCode: String = ""
    @State private var licenseKey: String = ""
    @State private var isLicenseSheetPresented = false
    @State private var toastMessage: String?
    @State private var tiltX: Double = 0
    @State private var tiltY: Double = 0
    @State private var isCardHovered = false
    
    
    private var theme: CotPassTheme {
        CotPassTheme.resolve(index: self.styleIndex)
    }
    
    private var activeTier: CotPassTier {
        CotPassLicense.validate(self.licenseKey) ?? .explorer
    }
    
    private var joinedText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: self.profileManager.activeProfile.createdAt)
    }
    
    
    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 14) {
                CotPassCardView(
                    theme: self.theme,
                    serialCode: self.serialCode,
                    holderName: self.profileManager.activeProfile.displayName,
                    joinedText: self.joinedText,
                    tier: self.activeTier
                )
                .rotation3DEffect(.degrees(self.tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
                .rotation3DEffect(.degrees(self.tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                .scaleEffect(self.isCardHovered ? 1.012 : 1.0)
                .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22), value: self.tiltX)
                .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22), value: self.tiltY)
                .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18), value: self.isCardHovered)
                .onContinuousHover { phase in
                    switch phase {
                        case .active(let pt):
                            self.isCardHovered = true
                            let nx = ((pt.x / 280.0) - 0.5) * 2.0
                            let ny = ((pt.y / 366.0) - 0.5) * 2.0
                            self.tiltY = max(-7, min(7, nx * 6.5))
                            self.tiltX = max(-7, min(7, -ny * 5.5))
                        case .ended:
                            self.isCardHovered = false
                            self.tiltX = 0
                            self.tiltY = 0
                    }
                }
                
                HStack(spacing: 16) {
                    PassActionIconButton(systemImage: "doc.on.doc", helpText: "复制 ASCII 通行证") {
                        self.copyASCIIToPasteboard()
                    }
                    
                    PassActionIconButton(systemImage: "arrow.down.circle", helpText: "导出高清 PNG 卡片") {
                        self.exportPassImage()
                    }
                    
                    PassActionIconButton(systemImage: "shuffle", helpText: "切换 ASCII 主题风格") {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) {
                            self.styleIndex = (self.styleIndex + 1) % CotPassTheme.allThemes.count
                        }
                        CotLocalDatabase.shared.set("\(self.styleIndex)", forKey: CotLocalDatabase.ConfigKey.cotPassStyleIndex)
                    }
                }
                
                if let toastMessage = self.toastMessage {
                    Text(toastMessage)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.top, 4)
            
            // Grouped Action Rows below card (matching reference layout)
            VStack(spacing: 0) {
                Button {
                    self.isLicenseSheetPresented = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "key")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        
                        Text("License 与激活")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Text(self.activeTier.summaryLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(self.activeTier == .explorer ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color(hexString: self.theme.matrixColorHex)))
                            .monospacedDigit()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Divider()
                    .padding(.leading, 44)
                
                Button {
                    self.onRequestMigrationExport()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        
                        Text("迁移全部数据到新 Mac（含端点、Key 与头像）")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            .frame(maxWidth: 460)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(self.cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(self.cardBorder, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            self.loadPassState()
        }
        .sheet(isPresented: self.$isLicenseSheetPresented) {
            CotPassLicenseSheet(
                licenseKey: self.$licenseKey,
                activeTier: self.activeTier,
                serialCode: self.serialCode
            ) { newKey in
                let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                self.licenseKey = trimmed
                CotLocalDatabase.shared.set(trimmed, forKey: CotLocalDatabase.ConfigKey.cotPassLicenseKey)
            }
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
        
        self.licenseKey = db.string(forKey: CotLocalDatabase.ConfigKey.cotPassLicenseKey)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    private func copyASCIIToPasteboard() {
        let text = self.theme.asciiRepresentation(
            serialCode: self.serialCode,
            holderName: self.profileManager.activeProfile.displayName,
            joinedDate: self.joinedText,
            tier: self.activeTier
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        self.showToast("已复制 ASCII 通行证到剪贴板")
    }
    
    
    private func exportPassImage() {
        let card = CotPassCardView(
            theme: self.theme,
            serialCode: self.serialCode,
            holderName: self.profileManager.activeProfile.displayName,
            joinedText: self.joinedText,
            tier: self.activeTier
        )
        .padding(20)
        .background(Color(hexString: self.theme.backgroundBottomHex))
        
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2.0
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:])
        else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "CotEditor-Pass-\(self.serialCode).png"
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            Task { @MainActor in
                do {
                    try pngData.write(to: url, options: .atomic)
                    self.showToast("已保存 PNG 到 \(url.lastPathComponent)")
                } catch {
                    self.showToast("导出失败：\(error.localizedDescription)")
                }
            }
        }
    }
    
    
    private func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.16)) {
            self.toastMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
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


// MARK: - Boarding Pass Card View

struct CotPassCardView: View {
    
    let theme: CotPassTheme
    let serialCode: String
    let holderName: String
    let joinedText: String
    let tier: CotPassTier
    
    
    var body: some View {
        let matrixColor = Color(hexString: self.theme.matrixColorHex)
        let accentColor = Color(hexString: self.theme.accentColorHex)
        let topBg = Color(hexString: self.theme.backgroundTopHex)
        let bottomBg = Color(hexString: self.theme.backgroundBottomHex)
        
        VStack(alignment: .leading, spacing: 0) {
            // Upper ASCII topographic matrix + Pixel Mascot
            ZStack(alignment: .top) {
                LinearGradient(colors: [topBg, bottomBg], startPoint: .top, endPoint: .bottom)
                
                ASCIITopographyCanvas(seed: self.theme.id, tint: matrixColor)
                
                // Top Bar
                HStack {
                    Text("COTEDITOR")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(matrixColor)
                    Spacer()
                    Text(self.serialCode)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                
                // Center Pixel Mascot
                PixelMascotView(bitmap: self.theme.bitmap, color: accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.top, 18)
            }
            .frame(height: 168)
            .clipped()
            
            Rectangle()
                .fill(matrixColor.opacity(0.18))
                .frame(height: 1)
            
            // Lower Terminal Metadata Block
            VStack(alignment: .leading, spacing: 0) {
                Text(self.tier == .explorer ? self.theme.title : self.tier.badgeTitle)
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                
                Text(self.theme.subtitle)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Color.white.opacity(0.42))
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text("STATUS")
                            .frame(width: 50, alignment: .leading)
                            .foregroundStyle(Color.white.opacity(0.42))
                        Text(">")
                            .foregroundStyle(Color.white.opacity(0.32))
                        Text(self.tier.statusLabel)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.black.opacity(0.88))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(accentColor, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                    }
                    
                    PassMetaRow(label: "HOLDER", value: self.holderName, valueColor: Color.white.opacity(0.86))
                    PassMetaRow(label: "JOINED", value: self.joinedText, valueColor: accentColor.opacity(0.9))
                    PassMetaRow(label: "ACCESS", value: self.tier.accessLabel, valueColor: accentColor.opacity(0.9))
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.top, 16)
                
                Spacer(minLength: 10)
                
                // Perforated ASCII dotted rule
                Text(String(repeating: "·", count: 38))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.18))
                    .lineLimit(1)
                
                HStack {
                    Text("COTEDITOR ▪ V1")
                    Spacer()
                    Text("WELCOME ABOARD")
                }
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.38))
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(bottomBg)
        }
        .frame(width: 280, height: 366)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(matrixColor.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 20, y: 10)
    }
}


private struct PassMetaRow: View {
    
    let label: String
    let value: String
    let valueColor: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Text(self.label)
                .frame(width: 50, alignment: .leading)
                .foregroundStyle(Color.white.opacity(0.42))
            Text(">")
                .foregroundStyle(Color.white.opacity(0.32))
            Text(self.value)
                .foregroundStyle(self.valueColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}


private struct ASCIITopographyCanvas: View {
    
    let seed: Int
    let tint: Color
    
    
    var body: some View {
        Canvas { context, size in
            let cols = 30
            let rows = 15
            let stepX = size.width / CGFloat(cols)
            let stepY = size.height / CGFloat(rows)
            
            for r in 0..<rows {
                for c in 0..<cols {
                    let fx = Double(c) * 0.34 + Double(self.seed) * 1.17
                    let fy = Double(r) * 0.42 + Double(self.seed) * 0.83
                    let wave = (sin(fx) * cos(fy) + sin((fx + fy) * 0.65) + 2.0) / 4.0
                    let dx = abs(Double(c) - Double(cols - 1) / 2.0)
                    let dy = abs(Double(r) - Double(rows - 1) / 2.0)
                    let centerClear = hypot(dx, dy * 1.4) < 3.4
                    guard !centerClear else { continue }
                    
                    let pt = CGPoint(x: (CGFloat(c) + 0.5) * stepX, y: (CGFloat(r) + 0.5) * stepY)
                    if wave > 0.62 {
                        let glyph = context.resolve(
                            Text("+")
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(self.tint.opacity(0.72))
                        )
                        context.draw(glyph, at: pt)
                    } else if wave > 0.42 {
                        let glyph = context.resolve(
                            Text("·")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(self.tint.opacity(0.36))
                        )
                        context.draw(glyph, at: pt)
                    } else if wave > 0.25 {
                        let dotRect = CGRect(x: pt.x - 0.8, y: pt.y - 0.8, width: 1.6, height: 1.6)
                        context.fill(Path(ellipseIn: dotRect), with: .color(self.tint.opacity(0.16)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}


private struct PixelMascotView: View {
    
    let bitmap: [String]
    let color: Color
    
    
    var body: some View {
        let pixel: CGFloat = 3.2
        VStack(spacing: 0.6) {
            ForEach(Array(self.bitmap.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0.6) {
                    ForEach(Array(row.enumerated()), id: \.offset) { colIndex, ch in
                        let isEye = (rowIndex == 2 && (colIndex == 2 || colIndex == 5)) && ch == "."
                        Rectangle()
                            .fill(ch == "#" ? self.color : (isEye ? Color.black.opacity(0.85) : Color.clear))
                            .frame(width: pixel, height: pixel)
                    }
                }
            }
        }
        .padding(7)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: self.color.opacity(0.35), radius: 8)
    }
}


private struct PassActionIconButton: View {
    
    let systemImage: String
    let helpText: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(self.isHovered ? .primary : .secondary)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(self.isHovered ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(self.helpText)
        .onHover { self.isHovered = $0 }
    }
}


// MARK: - License Sheet

private struct CotPassLicenseSheet: View {
    
    @Environment(\.dismiss) private var dismiss
    @Binding var licenseKey: String
    let activeTier: CotPassTier
    let serialCode: String
    let onSaveKey: (String) -> Void
    
    @State private var draftKey: String = ""
    @State private var validationMessage: String?
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CotEditor 通行证与授权")
                        .font(.headline)
                    Text("编号 \(self.serialCode) · 当前档位：\(self.activeTier.summaryLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(self.activeTier.badgeTitle)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("输入授权码（支持格式：`COT-PRO-XXXX-XXXX` 或 `COT-FOUNDER-XXXX-XXXX`）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    TextField("COT-PRO-2026-PASS", text: self.$draftKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                    
                    Button("激活") {
                        if let tier = CotPassLicense.validate(self.draftKey) {
                            self.onSaveKey(self.draftKey)
                            self.validationMessage = "✓ 已激活 \(tier.badgeTitle)"
                        } else {
                            self.validationMessage = "格式无效，请检查授权码前缀（COT-PRO- / COT-FOUNDER-）"
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(self.draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
                if let validationMessage = self.validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(validationMessage.hasPrefix("✓") ? Color.green : Color.orange)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Pro / Founder 规划权益（本地优先，无强制联网锁）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("• 全套 ASCII 通行证样式与个性化高清导出\n• 完整 SQLite 单文件跨机迁移（含端点、API Key、头像与 Bots 配置）\n• 后续云端实时同步与团队周报协作配额")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            HStack {
                if self.activeTier != .explorer {
                    Button("停用授权", role: .destructive) {
                        self.draftKey = ""
                        self.onSaveKey("")
                        self.validationMessage = "已恢复 Explorer 档位"
                    }
                }
                Spacer()
                Button("完成") {
                    self.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            self.draftKey = self.licenseKey
        }
    }
}
