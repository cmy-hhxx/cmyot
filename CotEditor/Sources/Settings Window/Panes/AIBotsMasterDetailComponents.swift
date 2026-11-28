//
//  AIBotsMasterDetailComponents.swift
//
//  CotEditor
//  https://coteditor.com
//

import AppKit
import SwiftUI

enum SelectedBotTarget: Equatable, Hashable {
    case builtIn(AIBotID)
    case custom(String)
    
    var botIDString: String {
        switch self {
            case .builtIn(let id): id.rawValue
            case .custom(let id): id
        }
    }
}


struct BotsGlobalProactiveCard: View {
    
    @State private var database = CotLocalDatabase.shared
    @State private var proactiveEnabled: Bool = true
    @State private var dndEnabled: Bool = true
    @State private var dndStartHour: Int = 23
    @State private var dndEndHour: Int = 8
    
    var body: some View {
        SettingsGroupCard(title: AppLanguage.text("主动消息", en: "Proactive Messaging")) {
            SettingsItemRow(label: AppLanguage.text("允许 Bot 主动发消息", en: "Allow Proactive DMs")) {
                Toggle("", isOn: self.$proactiveEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: self.proactiveEnabled) { _, next in
                        self.database.set(next ? "true" : "false", forKey: CotLocalDatabase.ConfigKey.proactiveMessagingEnabled)
                    }
            }
            
            Divider().padding(.leading, 14)
            
            HStack(alignment: .center, spacing: 10) {
                Text(AppLanguage.text("免打扰", en: "Quiet Hours"))
                    .font(.system(size: 13))
                
                Spacer(minLength: 8)
                
                if self.dndEnabled {
                    Picker("", selection: self.$dndStartHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(Self.hourLabel(hour))
                                .font(.system(size: 12).monospacedDigit())
                                .tag(hour)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 76)
                    .onChange(of: self.dndStartHour) { _, next in
                        self.database.set("\(next)", forKey: CotLocalDatabase.ConfigKey.proactiveDndStartHour)
                    }
                    
                    Text("→")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    Picker("", selection: self.$dndEndHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(Self.hourLabel(hour))
                                .font(.system(size: 12).monospacedDigit())
                                .tag(hour)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 76)
                    .onChange(of: self.dndEndHour) { _, next in
                        self.database.set("\(next)", forKey: CotLocalDatabase.ConfigKey.proactiveDndEndHour)
                    }
                }
                
                Toggle("", isOn: self.$dndEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: self.dndEnabled) { _, next in
                        self.database.set(next ? "true" : "false", forKey: CotLocalDatabase.ConfigKey.proactiveDndEnabled)
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .onAppear {
            self.loadSettings()
        }
    }
    
    
    private func loadSettings() {
        let enabledRaw = self.database.string(forKey: CotLocalDatabase.ConfigKey.proactiveMessagingEnabled, default: "true")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let dndRaw = self.database.string(forKey: CotLocalDatabase.ConfigKey.proactiveDndEnabled, default: "true")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.proactiveEnabled = (enabledRaw != "false" && enabledRaw != "0")
        self.dndEnabled = (dndRaw != "false" && dndRaw != "0")
        self.dndStartHour = Int(self.database.string(forKey: CotLocalDatabase.ConfigKey.proactiveDndStartHour, default: "23")) ?? 23
        self.dndEndHour = Int(self.database.string(forKey: CotLocalDatabase.ConfigKey.proactiveDndEndHour, default: "8")) ?? 8
    }
    
    
    private static func hourLabel(_ hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        return String(format: "%02d:00", h)
    }
}


struct BotMasterListSidebar: View {
    
    @Binding var selectedTarget: SelectedBotTarget
    let builtInBots: [AIBotID]
    let customBots: [CustomBotProfile]
    let botStore: AIBotStore
    let cardSurface: Color
    let cardBorder: Color
    let onCreateBot: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    self.sectionHeader(AppLanguage.text("总管", en: "Butler"))
                    self.builtInRow(.butler)
                    
                    self.sectionHeader(AppLanguage.text("内置", en: "Built-in"))
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(self.builtInBots.filter { $0 != .butler }) { botID in
                            self.builtInRow(botID)
                        }
                    }
                    
                    if !self.customBots.isEmpty {
                        self.sectionHeader(AppLanguage.text("自定义", en: "Custom"))
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(self.customBots) { custom in
                                BotMasterRow(
                                    title: custom.name,
                                    accentHex: custom.accentHex,
                                    avatarImage: self.botStore.resolvedAvatarImage(forBotID: custom.id, pointSize: 22),
                                    isSelected: self.selectedTarget == .custom(custom.id),
                                    isEnabled: custom.isEnabled,
                                    onSelect: { self.selectedTarget = .custom(custom.id) }
                                )
                            }
                        }
                    }
                }
                .padding(8)
            }
            
            Divider()
            
            Button(action: self.onCreateBot) {
                Label(AppLanguage.text("新建 Bot", en: "New Bot"), systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
        .frame(width: 172)
        .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
    }
    
    
    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.top, 2)
    }
    
    
    @ViewBuilder
    private func builtInRow(_ botID: AIBotID) -> some View {
        let cfg = self.botStore.config(for: botID)
        BotMasterRow(
            title: self.botStore.resolvedName(for: botID),
            accentHex: botID.accentHex,
            avatarImage: self.botStore.resolvedPortraitImage(for: botID, pointWidth: 22, pointHeight: 22, cachedOnly: true),
            isSelected: self.selectedTarget == .builtIn(botID),
            isEnabled: cfg.isEnabled,
            onSelect: { self.selectedTarget = .builtIn(botID) }
        )
    }
}


private struct BotMasterRow: View {
    
    let title: String
    let accentHex: String
    let avatarImage: NSImage?
    let isSelected: Bool
    let isEnabled: Bool
    let onSelect: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    
    var body: some View {
        let isDark = (self.colorScheme == .dark)
        let accent = Color(hexString: self.accentHex)
        let fillColor: Color = if self.isSelected {
            Color.primary.opacity(isDark ? 0.12 : 0.08)
        } else if self.isHovered {
            Color.primary.opacity(isDark ? 0.06 : 0.04)
        } else {
            .clear
        }
        
        Button(action: self.onSelect) {
            HStack(spacing: 8) {
                ZStack {
                    if let avatarImage {
                        Image(nsImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(accent.opacity(0.16))
                        Text(String(self.title.prefix(1)))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                }
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .opacity(self.isEnabled ? 1.0 : 0.45)
                
                Text(self.title)
                    .font(.system(size: 12.5, weight: self.isSelected ? .semibold : .regular))
                    .foregroundStyle(self.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .background(fillColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { self.isHovered = $0 }
    }
}


struct BotProactiveAndWorkspaceCard: View {
    
    let botIDString: String
    @Binding var proactiveLevel: BotProactiveLevel
    let onProactiveChanged: (BotProactiveLevel) -> Void
    
    @State private var database = CotLocalDatabase.shared
    @State private var workspaces: [ButlerWorkspaceRecord] = []
    @State private var selectedWorkspaceID: String = ""
    
    var body: some View {
        SettingsGroupCard(title: AppLanguage.text("主动与工作区", en: "Proactive & Workspace")) {
            SettingsItemRow(label: AppLanguage.text("主动频率", en: "Proactive")) {
                Picker("", selection: self.$proactiveLevel) {
                    ForEach(BotProactiveLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 174)
                .onChange(of: self.proactiveLevel) { _, next in
                    self.onProactiveChanged(next)
                }
            }
            
            Divider().padding(.leading, 14)
            
            SettingsItemRow(label: AppLanguage.text("专属工作区", en: "Workspace")) {
                Picker("", selection: self.$selectedWorkspaceID) {
                    Text(AppLanguage.text("无", en: "None")).tag("")
                    ForEach(self.workspaces) { ws in
                        Text(ws.name).tag(ws.id)
                    }
                }
                .labelsHidden()
                .frame(width: 174)
                .onChange(of: self.selectedWorkspaceID) { _, nextID in
                    if nextID.isEmpty {
                        self.database.clearBotFromWorkspaces(botID: self.botIDString)
                    } else {
                        self.database.assignButlerWorkspace(id: nextID, botID: self.botIDString)
                    }
                    CotButlerManager.shared.reloadFromDatabase()
                }
            }
        }
        .task(id: self.botIDString) {
            self.reloadWorkspaces()
        }
    }
    
    
    private func reloadWorkspaces() {
        self.workspaces = self.database.fetchButlerWorkspaces()
        self.selectedWorkspaceID = self.database.findButlerWorkspace(botID: self.botIDString)?.id ?? ""
    }
}


struct CustomBotInspectorView: View {
    
    let customBot: CustomBotProfile
    let cardSurface: Color
    let cardBorder: Color
    let onEdit: () -> Void
    
    @State private var botStore = AIBotStore.shared
    @State private var proactiveLevel: BotProactiveLevel = .off
    
    var body: some View {
        let accent = Color(hexString: self.customBot.accentHex)
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroupCard(title: AppLanguage.text("身份", en: "Identity")) {
                HStack(spacing: 12) {
                    ZStack {
                        if let img = self.botStore.resolvedAvatarImage(forBotID: self.customBot.id, pointSize: 44) {
                            Image(nsImage: img).resizable().scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(accent.opacity(0.16))
                            Text(String(self.customBot.name.prefix(1)))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.customBot.name)
                            .font(.system(size: 14, weight: .semibold))
                        Text(self.customBot.handle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(AppLanguage.text("打开对话", en: "Open Chat")) {
                        _ = CotButlerManager.shared.openDirectChat(botID: self.customBot.id)
                        CotButlerManager.shared.requestOpenHub()
                    }
                    .controlSize(.small)
                    
                    Button(AppLanguage.text("编辑", en: "Edit"), action: self.onEdit)
                        .controlSize(.small)
                }
                .padding(12)
            }
            
            SettingsGroupCard(title: AppLanguage.text("模型", en: "Model")) {
                SettingsItemRow(label: AppLanguage.text("当前模型", en: "Model")) {
                    HStack(spacing: 8) {
                        Text(self.customBot.modelOverride.isEmpty
                             ? AppLanguage.text("跟随默认", en: "Default")
                             : self.customBot.modelOverride)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Button(AppLanguage.text("修改", en: "Change"), action: self.onEdit)
                            .controlSize(.small)
                    }
                }
            }
            
            BotProactiveAndWorkspaceCard(
                botIDString: self.customBot.id,
                proactiveLevel: self.$proactiveLevel,
                onProactiveChanged: { nextLevel in
                    var updated = self.customBot
                    updated.proactiveLevel = nextLevel
                    self.botStore.updateCustomBot(updated)
                }
            )
        }
        .task(id: self.customBot.id) {
            self.proactiveLevel = self.customBot.proactiveLevel
        }
    }
}
