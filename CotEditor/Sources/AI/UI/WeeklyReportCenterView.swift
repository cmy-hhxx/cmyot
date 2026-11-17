//
//  WeeklyReportCenterView.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-11-17.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 1024jp
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

/// Controls the dedicated 周报中心 (Weekly Report Center) window.
@MainActor final class WeeklyReportWindowController: NSWindowController {
    
    static let shared = WeeklyReportWindowController()
    
    enum InitialMode: Sendable {
        case history
        case generator
    }
    
    private let state = WeeklyReportCenterState()
    
    private init() {
        
        let rootView = WeeklyReportCenterView(state: self.state)
        let hostingController = NSHostingController(rootView: rootView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "ai.weeklyCenter.windowTitle", defaultValue: "周报中心", table: "AI")
        window.setContentSize(NSSize(width: 980, height: 660))
        window.minSize = NSSize(width: 760, height: 500)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.center()
        
        super.init(window: window)
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    /// Brings the Weekly Report Center forward inside the current document window when available
    /// (falling back to the standalone window only when no document window is open).
    func showWindow(mode: InitialMode = .history, selectingReportID: String? = nil) {
        
        if let activeWC = (NSApp.mainWindow?.windowController as? DocumentWindowController)
            ?? NSApp.orderedWindows.compactMap({ $0.windowController as? DocumentWindowController }).first,
           let contentVC = activeWC.workspaceContentViewController
        {
            contentVC.showInWindowCenter(.weeklyReports, weeklyMode: mode, selectingReportID: selectingReportID)
            activeWC.window?.makeKeyAndOrderFront(nil)
            return
        }
        
        CotLocalDatabase.shared.reloadWeeklyReports()
        self.state.isGeneratorActive = (mode == .generator)
        if let selectingReportID {
            self.state.selectedReportID = selectingReportID
        } else if self.state.selectedReportID == nil {
            self.state.selectedReportID = CotLocalDatabase.shared.weeklyReports.first?.id
        }
        if mode == .generator {
            self.state.refreshOpenSources()
        }
        
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    
    /// Opens a stored historical weekly report cleanly in the active window's Markdown tab (or a standalone window if needed).
    func openReportInEditor(_ report: StoredWeeklyReport) {
        
        if let activeWC = (NSApp.mainWindow?.windowController as? DocumentWindowController)
            ?? NSApp.orderedWindows.compactMap({ $0.windowController as? DocumentWindowController }).first,
           let docVC = activeWC.documentViewController
        {
            activeWC.workspaceContentViewController?.hideInWindowCenter()
            docVC.openStoredWeeklyReport(report)
            activeWC.window?.makeKeyAndOrderFront(nil)
            return
        }
        
        guard let controller = NSDocumentController.shared as? DocumentController else { return }
        
        // Reuse if already open
        for case let existing as Document in controller.documents where existing.databaseDocumentID == "weekly:\(report.id)" {
            existing.makeWindowControllers()
            existing.showWindows()
            return
        }
        
        do {
            let document = try controller.openUntitledDocument(content: report.content, title: report.title, display: true)
            document.databaseDocumentID = "weekly:\(report.id)"
            document.setSyntax(name: SyntaxName.markdown)
            document.updateChangeCount(.changeCleared)
        } catch {
            NSApp.presentError(error)
        }
    }
}


@MainActor @Observable final class WeeklyReportCenterState {
    
    struct OpenSourceItem: Identifiable {
        let id: String
        let title: String
        let content: String
        var isSelected: Bool
    }
    
    var selectedReportID: String?
    var searchText: String = ""
    var isGeneratorActive: Bool = false
    var statusBanner: String?
    
    // Generator fields
    var authorName: String = CotLocalDatabase.shared.weeklyReportAuthor
    var customNotes: String = ""
    var fragmentsText: String = CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.weeklyReportFragments)
    var openSources: [OpenSourceItem] = []
    var generatedOutput: String = ""
    var isGenerating: Bool = false
    var generationError: String?
    
    func refreshOpenSources() {
        
        self.authorName = CotLocalDatabase.shared.weeklyReportAuthor
        self.fragmentsText = CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.weeklyReportFragments)
        
        var items: [OpenSourceItem] = []
        var seen = Set<ObjectIdentifier>()
        for window in NSApp.orderedWindows {
            guard let docVC = (window.windowController as? DocumentWindowController)?.documentViewController else { continue }
            for pane in docVC.editorViewControllers {
                for tab in pane.tabs {
                    let doc = tab.document
                    let objID = ObjectIdentifier(doc)
                    guard seen.insert(objID).inserted else { continue }
                    let text = doc.textStorage.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    // Avoid pre-selecting a historical weekly report that was opened just for reading
                    let isHistoricWeekly = doc.databaseDocumentID.hasPrefix("weekly:")
                    items.append(OpenSourceItem(
                        id: "\(objID.hashValue)",
                        title: doc.displayName,
                        content: doc.textStorage.string,
                        isSelected: !isHistoricWeekly
                    ))
                }
            }
        }
        self.openSources = items
    }
}


struct WeeklyReportCenterView: View {
    
    @Bindable var state: WeeklyReportCenterState
    var onOpenReport: ((StoredWeeklyReport) -> Void)? = nil
    @State private var db = CotLocalDatabase.shared
    @State private var isEditingSelected = false
    @State private var editingDraft = ""
    @State private var copiedFlag = false
    
    var body: some View {
        
        HStack(spacing: 0) {
            self.sidebar
                .frame(width: 295)
            
            Divider()
            
            Group {
                if self.state.isGeneratorActive {
                    self.generatorView
                } else if let selected = self.selectedReport {
                    self.detailView(for: selected)
                } else {
                    self.emptyDetailView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if self.state.selectedReportID == nil {
                self.state.selectedReportID = self.db.weeklyReports.first?.id
            }
            self.state.refreshOpenSources()
        }
    }
    
    
    // MARK: Sidebar
    
    private var filteredReports: [StoredWeeklyReport] {
        
        let query = self.state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return self.db.weeklyReports }
        return self.db.weeklyReports.filter { report in
            report.title.lowercased().contains(query)
                || report.periodLabel.lowercased().contains(query)
                || report.yearMonth.lowercased().contains(query)
                || report.content.lowercased().contains(query)
        }
    }
    
    private var groupedYearMonths: [(month: String, reports: [StoredWeeklyReport])] {
        
        let dict = Dictionary(grouping: self.filteredReports, by: \.yearMonth)
        return dict.keys.sorted(by: >).map { month in
            let sorted = (dict[month] ?? []).sorted { lhs, rhs in
                if lhs.periodLabel != rhs.periodLabel {
                    return lhs.periodLabel > rhs.periodLabel
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            return (month, sorted)
        }
    }
    
    private var selectedReport: StoredWeeklyReport? {
        
        guard let id = self.state.selectedReportID else { return self.filteredReports.first }
        return self.db.weeklyReports.first(where: { $0.id == id })
    }
    
    private var sidebar: some View {
        
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("历史周报库", systemImage: "calendar.badge.clock")
                        .font(.headline)
                    Spacer()
                    Text("\(self.db.weeklyReports.count) 篇")
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                
                TextField("搜索模块、关键词或日期…", text: self.$state.searchText)
                    .textFieldStyle(.roundedBorder)
                
                HStack(spacing: 6) {
                    Button {
                        self.state.isGeneratorActive = true
                        self.state.refreshOpenSources()
                    } label: {
                        Label("写本周周报", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button("导入…") {
                        self.runImportPanel()
                    }
                    .controlSize(.small)
                    .help("从 .zip 压缩包、文件夹或 .md 文件导入历史周报")
                }
                
                if let banner = self.state.statusBanner {
                    Text(banner)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            
            Divider()
            
            List(selection: self.$state.selectedReportID) {
                ForEach(self.groupedYearMonths, id: \.month) { group in
                    Section {
                        ForEach(group.reports) { report in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Text(report.periodLabel)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    Spacer()
                                }
                                Text(report.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                            .tag(report.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                self.isEditingSelected = false
                                self.state.isGeneratorActive = false
                                self.state.selectedReportID = report.id
                            }
                        }
                    } header: {
                        Text("\(group.month)（\(group.reports.count) 篇）")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
    
    
    // MARK: Detail Viewer / Editor
    
    private func detailView(for report: StoredWeeklyReport) -> some View {
        
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(report.title)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 8) {
                        Text("月份：\(report.yearMonth)")
                        Text("·")
                        Text("周期：\(report.periodLabel)")
                        if let source = report.sourcePath {
                            Text("·")
                            Text(source)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(self.copiedFlag ? "已拷贝 ✓" : "拷贝原文") {
                    let pboard = NSPasteboard.general
                    pboard.clearContents()
                    pboard.setString(report.content, forType: .string)
                    self.copiedFlag = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        self.copiedFlag = false
                    }
                }
                .controlSize(.small)
                
                Button("在编辑器打开") {
                    if let onOpenReport = self.onOpenReport {
                        onOpenReport(report)
                    } else {
                        WeeklyReportWindowController.shared.openReportInEditor(report)
                    }
                }
                .controlSize(.small)
                
                if self.isEditingSelected {
                    Button("保存修改") {
                        self.db.saveWeeklyReport(
                            id: report.id,
                            periodLabel: report.periodLabel,
                            yearMonth: report.yearMonth,
                            title: report.title,
                            content: self.editingDraft,
                            sourcePath: report.sourcePath,
                            isEnhanced: false
                        )
                        self.isEditingSelected = false
                        self.state.statusBanner = "已保存对 \(report.periodLabel) 的修改"
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button("编辑") {
                        self.editingDraft = report.content
                        self.isEditingSelected = true
                    }
                    .controlSize(.small)
                }
                
                Button(role: .destructive) {
                    self.db.deleteWeeklyReport(id: report.id)
                    if self.state.selectedReportID == report.id {
                        self.state.selectedReportID = self.db.weeklyReports.first?.id
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .help("从数据库移除这篇周报")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            
            Divider()
            
            if self.isEditingSelected {
                TextEditor(text: self.$editingDraft)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(12)
            } else {
                ScrollView {
                    Text(report.content)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }
    
    
    private var emptyDetailView: some View {
        
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("还没有历史周报")
                .font(.headline)
            Text("点击左侧「导入…」即可一键导入周报压缩包 (.zip) 或 Markdown 文件夹。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("导入历史周报 (.zip / 文件夹)…") {
                self.runImportPanel()
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    
    // MARK: Weekly Report Generator Workbench
    
    private var generatorView: some View {
        
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("✨ 本周周报生成（说人话 · 严守历史规范）")
                        .font(.title3.weight(.semibold))
                    Text("自动喂给 AI 最近 2 篇真实历史周报作为语气/排版范例，严禁“赋能/抓手/闭环”等黑话")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("返回查看历史") {
                    self.state.isGeneratorActive = false
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Text("署名：")
                            .font(.subheadline.weight(.medium))
                        TextField("陈明扬", text: self.$state.authorName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                            .onChange(of: self.state.authorName) { _, newVal in
                                let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    self.db.weeklyReportAuthor = trimmed
                                }
                            }
                        
                        Text("默认周期：\(AIService.currentWeekPeriodLabel())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        let refs = self.db.styleReferenceWeeklyReports(limit: 2)
                        if !refs.isEmpty {
                            Text("已自动参考范例：\(refs.map(\.periodLabel).joined(separator: "、"))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if !self.state.openSources.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("从当前打开的编辑器窗口采集素材（勾选纳入）：")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Button("刷新列表") {
                                    self.state.refreshOpenSources()
                                }
                                .controlSize(.mini)
                            }
                            
                            ForEach(self.$state.openSources) { $source in
                                Toggle(isOn: $source.isSelected) {
                                    Text("\(source.title)（\(source.content.count) 字）")
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("本周补充记录 / 做完的事情 / 遇到的问题：")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                        }
                        TextEditor(text: self.$state.customNotes)
                            .font(.system(size: 12.5))
                            .frame(height: 110)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                    }
                    
                    if !self.state.fragmentsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("已随手记入的周报素材片段（会一并合并）：")
                                    .font(.caption.weight(.medium))
                                Spacer()
                                Button("清空素材缓存") {
                                    self.db.clearWeeklyReportFragments()
                                    self.state.fragmentsText = ""
                                }
                                .controlSize(.mini)
                            }
                            TextEditor(text: self.$state.fragmentsText)
                                .font(.system(size: 11.5))
                                .frame(height: 75)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                        }
                    }
                    
                    HStack(spacing: 10) {
                        Button {
                            self.runWeeklyReportGeneration()
                        } label: {
                            if self.state.isGenerating {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("正在按规范生成（说人话版）…")
                                }
                            } else {
                                Label("AI 一键生成本周周报", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(self.state.isGenerating)
                        
                        if !self.state.generatedOutput.isEmpty {
                            Button("存入周报库并在编辑器打开") {
                                let saved = self.db.saveGeneratedWeeklyReport(content: self.state.generatedOutput)
                                self.state.statusBanner = "已保存并归档周报：\(saved.periodLabel)"
                                self.state.selectedReportID = saved.id
                                self.state.isGeneratorActive = false
                                if let onOpenReport = self.onOpenReport {
                                    onOpenReport(saved)
                                } else {
                                    WeeklyReportWindowController.shared.openReportInEditor(saved)
                                }
                            }
                            
                            Button("只存周报库") {
                                let saved = self.db.saveGeneratedWeeklyReport(content: self.state.generatedOutput)
                                self.state.statusBanner = "已存周报：\(saved.periodLabel)"
                            }
                        }
                    }
                    
                    if let error = self.state.generationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    if !self.state.generatedOutput.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("生成结果预览（可直接微调后存入周报库）：")
                                .font(.subheadline.weight(.medium))
                            TextEditor(text: self.$state.generatedOutput)
                                .font(.system(size: 13))
                                .frame(minHeight: 240)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.4)))
                        }
                    }
                }
                .padding(18)
            }
        }
    }
    
    
    // MARK: Actions
    
    private func runImportPanel() {
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.zip, .folder, UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.message = "选择历史周报 .zip 压缩包、周报文件夹或 .md 文件，自动解析月份并存入本地数据库"
        
        let beginHandler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            Task { @MainActor in
                do {
                    let count = try self.db.importWeeklyReports(fromURLs: panel.urls)
                    self.state.statusBanner = "成功导入 \(count) 篇周报"
                    if self.state.selectedReportID == nil {
                        self.state.selectedReportID = self.db.weeklyReports.first?.id
                    }
                } catch {
                    self.state.statusBanner = "导入失败：\(error.localizedDescription)"
                }
            }
        }
        
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: beginHandler)
        } else {
            beginHandler(panel.runModal())
        }
    }
    
    
    private func runWeeklyReportGeneration() {
        
        guard AIService.shared.isConfigured else {
            self.state.generationError = "尚未配置 AI 模型与 API Key，请先打开「设置 → AI」完成配置。"
            (NSApp.delegate as? AppDelegate)?.showAIPreferences(nil)
            return
        }
        
        var materialParts: [String] = []
        for source in self.state.openSources where source.isSelected {
            let trimmed = source.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            materialParts.append("【文档：\(source.title)】\n\(trimmed)")
        }
        
        let custom = self.state.customNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            materialParts.append("【手动补充记录】\n\(custom)")
        }
        
        let frags = self.state.fragmentsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawInput: String
        if !materialParts.isEmpty {
            rawInput = materialParts.joined(separator: "\n\n---\n\n")
        } else if !frags.isEmpty {
            rawInput = "【本周积累片段】\n\(frags)"
        } else {
            self.state.generationError = "请至少勾选一份文档、或在上方输入框填几条本周做过的事。"
            return
        }
        
        self.db.set(frags, forKey: CotLocalDatabase.ConfigKey.weeklyReportFragments)
        self.state.generationError = nil
        self.state.isGenerating = true
        self.state.generatedOutput = ""
        
        Task {
            do {
                let result = try await AIService.shared.run(.weeklyReport, on: rawInput) { partial in
                    self.state.generatedOutput = partial
                }
                self.state.generatedOutput = MarkdownTableFormatter.formatTables(in: result)
            } catch {
                self.state.generationError = error.localizedDescription
            }
            self.state.isGenerating = false
        }
    }
}
