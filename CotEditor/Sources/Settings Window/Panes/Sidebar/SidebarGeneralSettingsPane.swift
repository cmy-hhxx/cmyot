//
//  SidebarGeneralSettingsPane.swift
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
import Defaults
import SwiftUI

/// Startup, language, autosave, stored documents management, and version metadata.
struct SidebarGeneralSettingsPane: View {
    
    @AppStorage(.quitAlwaysKeepsWindows) private var quitAlwaysKeepsWindows
    @AppStorage(.noDocumentOnLaunchOption) private var noDocumentOnLaunchOption
    @AppStorage(.enablesAutosaveInPlace) private var enablesAutosaveInPlace
    
    @State private var language: AppLanguage = .current
    @State private var isLanguageConfirmationPresented = false
    @State private var isShowingStoredDocs = false
    @State private var isShowingVersionDetails = false
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            if self.isShowingStoredDocs {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            self.isShowingStoredDocs = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text(AppLanguage.text("返回通用设置", en: "Back to General"))
                                .font(.system(size: 12.5, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    SettingsGroupCard(title: AppLanguage.text("本地文档库", en: "Document Vault")) {
                        StoredDocumentsSheetView(isEmbeddedInline: true) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                self.isShowingStoredDocs = false
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                self.generalMainContent
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
    }
    
    
    private var generalMainContent: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            SettingsGroupCard(title: AppLanguage.text("启动与语言", en: "Startup & Language")) {
                SettingsItemRow(label: AppLanguage.text("界面语言", en: "Language")) {
                    Picker("", selection: self.$language) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(verbatim: lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                    .onChange(of: self.language) { _, newValue in
                        newValue.apply()
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)) {
                            self.isLanguageConfirmationPresented = true
                        }
                    }
                }
                
                if self.isLanguageConfirmationPresented {
                    SettingsRowDivider()
                    HStack(spacing: 10) {
                        Text(AppLanguage.text("语言已切换，重启后完整生效", en: "Restart to apply language"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(AppLanguage.text("稍后", en: "Later")) {
                            withAnimation(.easeOut(duration: 0.14)) {
                                self.isLanguageConfirmationPresented = false
                            }
                        }
                        .controlSize(.small)
                        Button(AppLanguage.text("立即重启", en: "Relaunch")) {
                            (NSApp.delegate as? AppDelegate)?.needsRelaunch = true
                            NSApp.terminate(nil)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("无文档启动动作", en: "When Opening Without Documents")) {
                    Picker("", selection: self.$noDocumentOnLaunchOption) {
                        Text(AppLanguage.text("新建空白文档", en: "Create New Document")).tag(NoDocumentOnLaunchOption.untitledDocument)
                        Text(AppLanguage.text("显示打开面板", en: "Show Open Panel")).tag(NoDocumentOnLaunchOption.openPanel)
                        Text(AppLanguage.text("不执行动作", en: "Do Nothing")).tag(NoDocumentOnLaunchOption.none)
                    }
                    .labelsHidden()
                    .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("启动时恢复上次窗口", en: "Restore Windows on Launch")) {
                    Toggle("", isOn: self.$quitAlwaysKeepsWindows)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("自动保存文档修改", en: "Autosave Documents")) {
                    Toggle("", isOn: self.$enablesAutosaveInPlace)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            
            SettingsGroupCard(title: AppLanguage.text("文档仓库", en: "Documents")) {
                SettingsItemRow(label: AppLanguage.text("本地文档库", en: "Document Vault")) {
                    Button(AppLanguage.text("管理文档", en: "Manage")) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            self.isShowingStoredDocs = true
                        }
                    }
                    .controlSize(.small)
                }
            }
            
            SettingsGroupCard(title: AppLanguage.text("关于版本", en: "Version")) {
                SettingsItemRow(label: "\(Bundle.main.bundleName) \(Bundle.main.shortVersion) (\(Bundle.main.bundleVersion))") {
                    Button(self.isShowingVersionDetails ? AppLanguage.text("收起", en: "Hide") : AppLanguage.text("详情", en: "Details")) {
                        withAnimation(.easeOut(duration: 0.16)) {
                            self.isShowingVersionDetails.toggle()
                        }
                    }
                    .controlSize(.small)
                }
                
                if self.isShowingVersionDetails {
                    SettingsRowDivider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bundle ID · \(Bundle.main.bundleIdentifier ?? "local.cmy.Cot")")
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Text("Data · \(CotLocalDatabase.shared.databaseURL.deletingLastPathComponent().path)")
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
    }
}
