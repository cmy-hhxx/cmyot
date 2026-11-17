//
//  DocumentCenterView.swift
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
import Observation
import SwiftUI
import UniformTypeIdentifiers

enum DocumentCenterFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case openNow = "已打开"
    case diskFiles = "本地文件"
    case drafts = "草稿笔记"
    
    var id: String { self.rawValue }
}


enum DocumentCenterSort: String, CaseIterable, Identifiable {
    case recent = "最近更新"
    case title = "名称"
    case length = "字数"
    
    var id: String { self.rawValue }
}


@MainActor @Observable final class DocumentCenterState {
    
    struct ManagedDocumentItem: Identifiable, Equatable {
        let id: String
        let dbRecordID: String?
        let title: String
        let filePath: String?
        let fileExists: Bool
        let syntax: String
        let content: String
        let updatedAt: Date
        let isOpenNow: Bool
        let isDirty: Bool
        let characterCount: Int
        let storedRecord: StoredDocumentRecord?
        
        var isDiskFile: Bool { self.filePath != nil }
        
        var locationSubtitle: String {
            if let filePath {
                return (filePath as NSString).abbreviatingWithTildeInPath
            }
            return "本软件云端/本地库笔记"
        }
    }
    
    var items: [ManagedDocumentItem] = []
    var selectedID: String?
    var searchText: String = ""
    var filter: DocumentCenterFilter = .all
    var sortOrder: DocumentCenterSort = .recent
    var statusBanner: String?
    
    private var liveDocsByID: [String: Document] = [:]
    
    func liveDocument(for id: String) -> Document? {
        
        self.liveDocsByID[id]
    }
    
    
    func refresh() {
        
        var liveByKey: [String: Document] = [:]
        var orderedOpenDocs: [Document] = []
        var seenPointers = Set<ObjectIdentifier>()
        
        for window in NSApp.orderedWindows {
            guard let docVC = (window.windowController as? DocumentWindowController)?.documentViewController else { continue }
            for pane in docVC.editorViewControllers {
                for tab in pane.tabs {
                    let doc = tab.document
                    guard seenPointers.insert(ObjectIdentifier(doc)).inserted else { continue }
                    orderedOpenDocs.append(doc)
                }
            }
        }
        for case let doc as Document in NSDocumentController.shared.documents {
            guard seenPointers.insert(ObjectIdentifier(doc)).inserted else { continue }
            orderedOpenDocs.append(doc)
        }
        
        var dbByCanonicalKey: [String: StoredDocumentRecord] = [:]
        for record in CotLocalDatabase.shared.documents {
            let key = Self.canonicalKey(filePath: record.filePath, rawID: record.id)
            if dbByCanonicalKey[key] == nil {
                dbByCanonicalKey[key] = record
            }
        }
        
        var merged: [ManagedDocumentItem] = []
        var usedKeys = Set<String>()
        
        for doc in orderedOpenDocs {
            guard !doc.databaseDocumentID.hasPrefix("weekly:") else { continue }
            let filePath = doc.fileURL?.standardizedFileURL.path(percentEncoded: false)
            let key = Self.canonicalKey(filePath: filePath, rawID: doc.databaseDocumentID)
            guard usedKeys.insert(key).inserted else { continue }
            
            liveByKey[key] = doc
            let dbMatch = dbByCanonicalKey[key]
            let content = doc.textStorage.string
            let dirty = doc.hasUncommittedChanges || doc.isDocumentEdited
            let modifiedDate = max(
                doc.lastManualSaveDate ?? .distantPast,
                doc.fileModificationDate ?? .distantPast,
                dbMatch?.updatedAt ?? Date()
            )
            
            merged.append(ManagedDocumentItem(
                id: key,
                dbRecordID: dbMatch?.id ?? (filePath ?? (doc.databaseDocumentID.hasPrefix("doc:") ? doc.databaseDocumentID : "doc:\(doc.databaseDocumentID)")),
                title: doc.displayName,
                filePath: filePath,
                fileExists: filePath.map { FileManager.default.fileExists(atPath: $0) } ?? false,
                syntax: doc.syntaxName,
                content: content,
                updatedAt: modifiedDate,
                isOpenNow: true,
                isDirty: dirty,
                characterCount: content.count,
                storedRecord: dbMatch ?? StoredDocumentRecord(
                    id: filePath ?? (doc.databaseDocumentID.hasPrefix("doc:") ? doc.databaseDocumentID : "doc:\(doc.databaseDocumentID)"),
                    title: doc.displayName,
                    filePath: filePath,
                    syntax: doc.syntaxName,
                    content: content,
                    highlightsJSON: "[]",
                    updatedAt: modifiedDate
                )
            ))
        }
        
        for record in CotLocalDatabase.shared.documents {
            guard !record.id.hasPrefix("weekly:") else { continue }
            let key = Self.canonicalKey(filePath: record.filePath, rawID: record.id)
            guard usedKeys.insert(key).inserted else { continue }
            
            let fileExists = record.filePath.map { FileManager.default.fileExists(atPath: $0) } ?? false
            merged.append(ManagedDocumentItem(
                id: key,
                dbRecordID: record.id,
                title: record.title,
                filePath: record.filePath,
                fileExists: fileExists,
                syntax: record.syntax,
                content: record.content,
                updatedAt: record.updatedAt,
                isOpenNow: false,
                isDirty: false,
                characterCount: record.content.count,
                storedRecord: record
            ))
        }
        
        self.liveDocsByID = liveByKey
        self.items = merged
        
        if let selectedID, merged.contains(where: { $0.id == selectedID }) {
            return
        }
        self.selectedID = merged.first?.id
    }
    
    
    private static func canonicalKey(filePath: String?, rawID: String) -> String {
        
        if let filePath, !filePath.isEmpty {
            return "file:\(URL(filePath: filePath).standardizedFileURL.path(percentEncoded: false))"
        }
        let clean = rawID.hasPrefix("doc:") ? String(rawID.dropFirst(4)) : rawID
        return "doc:\(clean)"
    }
}


struct DocumentCenterView: View {
    
    @Bindable var state: DocumentCenterState
    var onOpenDocument: ((Document?, StoredDocumentRecord?, _ splitRight: Bool) -> Void)? = nil
    var onCreateNewDocument: (() -> Void)? = nil
    var onOpenDiskURLs: (([URL]) -> Void)? = nil
    
    @State private var db = CotLocalDatabase.shared
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @State private var copiedFlag = false
    
    var body: some View {
        
        HStack(spacing: 0) {
            self.sidebar
                .frame(width: 310)
            
            Divider()
            
            Group {
                if let item = self.selectedItem {
                    self.detailView(for: item)
                } else {
                    self.emptyView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            self.state.refresh()
        }
        .onChange(of: self.db.documents) { _, _ in
            self.state.refresh()
        }
    }
    
    
    // MARK: Filtering & Sorting
    
    private var filteredItems: [DocumentCenterState.ManagedDocumentItem] {
        
        let query = self.state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = self.state.items.filter { item in
            switch self.state.filter {
                case .all: break
                case .openNow: guard item.isOpenNow else { return false }
                case .diskFiles: guard item.isDiskFile else { return false }
                case .drafts: guard !item.isDiskFile else { return false }
            }
            
            guard !query.isEmpty else { return true }
            return item.title.lowercased().contains(query)
                || (item.filePath?.lowercased().contains(query) ?? false)
                || item.syntax.lowercased().contains(query)
                || item.content.lowercased().contains(query)
        }
        
        return filtered.sorted { lhs, rhs in
            switch self.state.sortOrder {
                case .recent:
                    if lhs.isOpenNow != rhs.isOpenNow {
                        return lhs.isOpenNow && !rhs.isOpenNow
                    }
                    return lhs.updatedAt > rhs.updatedAt
                case .title:
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                case .length:
                    return lhs.characterCount > rhs.characterCount
            }
        }
    }
    
    
    private var selectedItem: DocumentCenterState.ManagedDocumentItem? {
        
        guard let selectedID = self.state.selectedID else { return self.filteredItems.first }
        return self.filteredItems.first(where: { $0.id == selectedID })
            ?? self.state.items.first(where: { $0.id == selectedID })
    }
    
    
    // MARK: Sidebar
    
    private var sidebar: some View {
        
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("文档中心", systemImage: "doc.on.doc")
                        .font(.headline)
                    Spacer()
                    Text("\(self.state.items.count) 份")
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                
                TextField("搜索标题、路径、语言或正文…", text: self.$state.searchText)
                    .textFieldStyle(.roundedBorder)
                
                Picker("筛选", selection: self.$state.filter) {
                    ForEach(DocumentCenterFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                
                HStack(spacing: 6) {
                    Button {
                        self.onCreateNewDocument?()
                    } label: {
                        Label("新建标签页", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button {
                        self.presentOpenPanel()
                    } label: {
                        Label("打开文件…", systemImage: "folder")
                    }
                    .controlSize(.small)
                    
                    Spacer()
                    
                    Picker("", selection: self.$state.sortOrder) {
                        ForEach(DocumentCenterSort.allCases) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 96)
                    .controlSize(.small)
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
            
            List(selection: self.$state.selectedID) {
                ForEach(self.filteredItems) { item in
                    self.sidebarRow(for: item)
                        .tag(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            self.open(item: item, splitRight: false)
                        }
                        .onTapGesture {
                            self.isRenaming = false
                            self.state.selectedID = item.id
                        }
                }
            }
            .listStyle(.sidebar)
        }
    }
    
    
    private func sidebarRow(for item: DocumentCenterState.ManagedDocumentItem) -> some View {
        
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(self.statusColor(for: item))
                    .frame(width: 7, height: 7)
                
                Text(item.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                if item.isOpenNow {
                    Text("打开中")
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
            
            HStack(spacing: 6) {
                Text(item.syntax)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                
                Text("·")
                    .foregroundStyle(.tertiary)
                
                Text("\(item.characterCount) 字")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(item.updatedAt, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            
            if let filePath = item.filePath {
                Text((filePath as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 3)
    }
    
    
    private func statusColor(for item: DocumentCenterState.ManagedDocumentItem) -> Color {
        
        if item.isDirty { return .orange }
        if item.isOpenNow || item.fileExists { return .green }
        return .secondary.opacity(0.5)
    }
    
    
    // MARK: Detail View
    
    private func detailView(for item: DocumentCenterState.ManagedDocumentItem) -> some View {
        
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    if self.isRenaming {
                        TextField("文档标题", text: self.$renameDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                            .onSubmit {
                                self.commitRename(for: item)
                            }
                        Button("确定") {
                            self.commitRename(for: item)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        Button("取消") {
                            self.isRenaming = false
                        }
                        .controlSize(.small)
                    } else {
                        Text(item.title)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                        
                        Button {
                            self.renameDraft = item.title
                            self.isRenaming = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("重命名文档")
                    }
                    
                    Spacer()
                    
                    self.saveBadge(for: item)
                }
                
                HStack(spacing: 10) {
                    Label(item.syntax, systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(item.characterCount) 字符")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(item.locationSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                HStack(spacing: 8) {
                    Button {
                        self.open(item: item, splitRight: false)
                    } label: {
                        Label("在当前窗口打开", systemImage: "macwindow")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button {
                        self.open(item: item, splitRight: true)
                    } label: {
                        Label("右侧分屏对照", systemImage: "rectangle.split.2x1")
                    }
                    .controlSize(.small)
                    
                    if item.isOpenNow, let liveDoc = self.state.liveDocument(for: item.id), item.isDirty {
                        Button {
                            liveDoc.performQuickSave(nil)
                            self.state.refresh()
                            self.state.statusBanner = "已保存「\(item.title)」"
                        } label: {
                            Label("保存 (⌘S)", systemImage: "square.and.arrow.down")
                        }
                        .controlSize(.small)
                    }
                    
                    Button(self.copiedFlag ? "已拷贝 ✓" : "拷贝全文") {
                        let pboard = NSPasteboard.general
                        pboard.clearContents()
                        pboard.setString(item.content, forType: .string)
                        self.copiedFlag = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            self.copiedFlag = false
                        }
                    }
                    .controlSize(.small)
                    
                    if let path = item.filePath, item.fileExists {
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
                        }
                        .controlSize(.small)
                    }
                    
                    Spacer()
                    
                    if let recordID = item.dbRecordID {
                        Button(role: .destructive) {
                            self.db.deleteDocument(id: recordID)
                            self.state.refresh()
                            self.state.statusBanner = "已从文档中心记录移除「\(item.title)」（磁盘文件不受影响）"
                        } label: {
                            Image(systemName: "trash")
                        }
                        .controlSize(.small)
                        .help("从文档中心历史记录中移除（不会删除本地磁盘文件）")
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            
            Divider()
            
            ScrollView {
                let preview = item.content.count > 40_000
                    ? String(item.content.prefix(40_000)) + "\n\n……（文档较长，点击上方「在当前窗口打开」查看全部内容）"
                    : (item.content.isEmpty ? "（空文档）" : item.content)
                
                Text(preview)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
    
    
    private func saveBadge(for item: DocumentCenterState.ManagedDocumentItem) -> some View {
        
        let (label, color): (String, Color) = if item.isDirty {
            ("未保存", .orange)
        } else if item.isOpenNow || item.fileExists {
            ("已保存", .green)
        } else {
            ("本地库快照", .secondary)
        }
        
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
    
    
    private var emptyView: some View {
        
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("文档中心")
                .font(.title3.weight(.semibold))
            Text("这里汇集了你通过 CotEditor 打开或创建的所有文件与笔记，点击左侧文档即可直接在当前窗口打开并管理保存状态。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 10) {
                Button("新建标签页") {
                    self.onCreateNewDocument?()
                }
                .buttonStyle(.borderedProminent)
                Button("从磁盘打开文件…") {
                    self.presentOpenPanel()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    
    // MARK: Actions
    
    private func open(item: DocumentCenterState.ManagedDocumentItem, splitRight: Bool) {
        
        let liveDoc = self.state.liveDocument(for: item.id)
        if let onOpenDocument = self.onOpenDocument {
            onOpenDocument(liveDoc, item.storedRecord, splitRight)
        } else if let liveDoc {
            liveDoc.makeWindowControllers()
            liveDoc.showWindows()
        } else if let path = item.filePath, FileManager.default.fileExists(atPath: path) {
            NSDocumentController.shared.openDocument(withContentsOf: URL(filePath: path), display: true) { _, _, _ in }
        }
    }
    
    
    private func commitRename(for item: DocumentCenterState.ManagedDocumentItem) {
        
        let trimmed = self.renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.isRenaming = false
            return
        }
        
        if let liveDoc = self.state.liveDocument(for: item.id) {
            do {
                let newName = try WorkspaceOrganizer.renameDocument(liveDoc, to: trimmed)
                self.state.statusBanner = "已重命名为「\(newName)」"
            } catch {
                self.state.statusBanner = "重命名失败：\(error.localizedDescription)"
            }
        } else if let recordID = item.dbRecordID, item.filePath == nil {
            self.db.renameDocument(oldID: recordID, newID: recordID, newTitle: trimmed, newFilePath: nil)
            self.state.statusBanner = "已重命名为「\(trimmed)」"
        }
        self.isRenaming = false
        self.state.refresh()
    }
    
    
    private func presentOpenPanel() {
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "选择一个或多个文档，直接在当前窗口中打开并纳入文档中心管理"
        
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        if let onOpenDiskURLs = self.onOpenDiskURLs {
            onOpenDiskURLs(panel.urls)
        } else {
            for url in panel.urls {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
        }
    }
}
