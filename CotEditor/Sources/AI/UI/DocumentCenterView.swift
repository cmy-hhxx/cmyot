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
    }
    
    var items: [ManagedDocumentItem] = []
    var selectedID: String?
    var searchText: String = ""
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
            let content = doc.textStorage.string
            let dirty = doc.hasUncommittedChanges || doc.isDocumentEdited
            
            // Skip transient empty scratch tabs that have never been written or saved
            if filePath == nil, content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !dirty {
                continue
            }
            
            let key = Self.canonicalKey(filePath: filePath, rawID: doc.databaseDocumentID)
            guard usedKeys.insert(key).inserted else { continue }
            
            liveByKey[key] = doc
            let dbMatch = dbByCanonicalKey[key]
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
    var onDeleteDocument: ((DocumentCenterState.ManagedDocumentItem) -> Void)? = nil
    var onCreateNewDocument: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    
    @State private var db = CotLocalDatabase.shared
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @State private var copiedFlag = false
    
    var body: some View {
        
        HStack(spacing: 0) {
            self.sidebar
                .frame(width: 268)
            
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 1)
            
            Group {
                if let item = self.selectedItem {
                    self.detailView(for: item)
                } else {
                    self.emptyView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            self.state.refresh()
        }
        .onChange(of: self.db.documents) { _, _ in
            self.state.refresh()
        }
    }
    
    
    // MARK: Filtering
    
    private var filteredItems: [DocumentCenterState.ManagedDocumentItem] {
        
        let query = self.state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = self.state.items.filter { item in
            guard !query.isEmpty else { return true }
            return item.title.lowercased().contains(query)
                || (item.filePath?.lowercased().contains(query) ?? false)
                || item.content.lowercased().contains(query)
        }
        
        return filtered.sorted { lhs, rhs in
            if lhs.isOpenNow != rhs.isOpenNow {
                return lhs.isOpenNow && !rhs.isOpenNow
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
    
    
    private var selectedItem: DocumentCenterState.ManagedDocumentItem? {
        
        guard let selectedID = self.state.selectedID else { return self.filteredItems.first }
        return self.filteredItems.first(where: { $0.id == selectedID })
            ?? self.filteredItems.first
    }
    
    
    // MARK: Sidebar
    
    private var sidebar: some View {
        
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(nsImage: WorkspaceCenterIcons.documentCenterIcon(isActive: false, size: NSSize(width: 15, height: 15)))
                        .renderingMode(.template)
                        .foregroundStyle(.secondary)
                    
                    Text("文档中心")
                        .font(.system(size: 13.5, weight: .semibold))
                    
                    Text("\(self.filteredItems.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    
                    Spacer()
                    
                    if let onDismiss = self.onDismiss {
                        Button {
                            onDismiss()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("返回")
                                    .font(.system(size: 11.5))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help("返回编辑器 (Esc)")
                    }
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                    
                    TextField("搜索文档…", text: self.$state.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                    
                    if !self.state.searchText.isEmpty {
                        Button {
                            self.state.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                
                if let banner = self.state.statusBanner {
                    Text(banner)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)
            
            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 1)
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(self.filteredItems) { item in
                        DocumentSidebarRow(
                            item: item,
                            isSelected: self.selectedItem?.id == item.id,
                            statusColor: self.statusColor(for: item),
                            onSelect: {
                                self.isRenaming = false
                                self.state.selectedID = item.id
                            },
                            onOpen: {
                                self.open(item: item, splitRight: false)
                            },
                            onOpenSplit: {
                                self.open(item: item, splitRight: true)
                            },
                            onDelete: {
                                self.delete(item: item)
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    
    private func statusColor(for item: DocumentCenterState.ManagedDocumentItem) -> Color {
        
        if item.isDirty { return .orange }
        if item.isOpenNow || item.fileExists { return .green }
        return .secondary.opacity(0.45)
    }
    
    
    // MARK: Detail View
    
    private func detailView(for item: DocumentCenterState.ManagedDocumentItem) -> some View {
        
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                if self.isRenaming {
                    TextField("文档标题", text: self.$renameDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
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
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    
                    Button {
                        self.renameDraft = item.title
                        self.isRenaming = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("重命名")
                    
                    Text("\(item.characterCount) 字")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
                
                HStack(spacing: 6) {
                    Button {
                        self.open(item: item, splitRight: false)
                    } label: {
                        Label("打开", systemImage: "macwindow")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button {
                        self.open(item: item, splitRight: true)
                    } label: {
                        Label("分屏", systemImage: "rectangle.split.2x1")
                    }
                    .controlSize(.small)
                    
                    Button(self.copiedFlag ? "已拷贝 ✓" : "拷贝") {
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
                    
                    Button(role: .destructive) {
                        self.delete(item: item)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .controlSize(.small)
                    .help("删除此文档记录（磁盘文件不受影响）")
                }
                .padding(.leading, 8)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            
            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 1)
            
            ScrollView {
                let preview = item.content.count > 40_000
                    ? String(item.content.prefix(40_000)) + "\n\n……（文档较长，点击上方「打开」查看全部内容）"
                    : (item.content.isEmpty ? "（空文档）" : item.content)
                
                Text(preview)
                    .font(.system(size: 13))
                    .lineSpacing(3.5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
    
    
    private var emptyView: some View {
        
        VStack(spacing: 10) {
            Image(nsImage: WorkspaceCenterIcons.documentCenterIcon(isActive: false, size: NSSize(width: 34, height: 34)))
                .renderingMode(.template)
                .foregroundStyle(.tertiary)
            
            Text(self.state.searchText.isEmpty ? "暂无文档" : "没有匹配的文档")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                if !self.state.searchText.isEmpty {
                    Button("清除搜索") {
                        self.state.searchText = ""
                    }
                    .controlSize(.small)
                }
                if let onCreateNewDocument = self.onCreateNewDocument {
                    Button("新建文档") {
                        onCreateNewDocument()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
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
    
    
    private func delete(item: DocumentCenterState.ManagedDocumentItem) {
        
        let list = self.filteredItems
        if let idx = list.firstIndex(where: { $0.id == item.id }) {
            let nextItem = list.indices.contains(idx + 1) ? list[idx + 1] : (idx > 0 ? list[idx - 1] : nil)
            self.state.selectedID = nextItem?.id
        }
        
        if let onDeleteDocument = self.onDeleteDocument {
            onDeleteDocument(item)
        } else if let recordID = item.dbRecordID {
            self.db.deleteDocument(id: recordID, filePath: item.filePath)
            self.state.refresh()
        }
        self.state.statusBanner = "已删除「\(item.title)」"
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
}


private struct DocumentSidebarRow: View {
    
    let item: DocumentCenterState.ManagedDocumentItem
    let isSelected: Bool
    let statusColor: Color
    var onSelect: () -> Void
    var onOpen: () -> Void
    var onOpenSplit: () -> Void
    var onDelete: () -> Void
    
    @State private var isHovered = false
    @State private var isTrashHovered = false
    
    var body: some View {
        
        HStack(spacing: 8) {
            Circle()
                .fill(self.statusColor)
                .frame(width: 6, height: 6)
            
            Text(self.item.title)
                .font(.system(size: 12.5, weight: self.isSelected ? .semibold : .regular))
                .foregroundStyle(self.isSelected ? Color.primary : Color.primary.opacity(0.88))
                .lineLimit(1)
            
            Spacer(minLength: 4)
            
            if self.isHovered || self.isSelected {
                Button {
                    self.onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(self.isTrashHovered ? Color.red : Color.secondary)
                        .frame(width: 22, height: 22)
                        .background(
                            self.isTrashHovered ? Color.red.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    self.isTrashHovered = hovering
                }
                .help("删除「\(self.item.title)」")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            self.isSelected
                ? Color.accentColor.opacity(0.13)
                : (self.isHovered ? Color.primary.opacity(0.045) : Color.clear),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            self.isHovered = hovering
        }
        .onTapGesture(count: 2) {
            self.onOpen()
        }
        .onTapGesture {
            self.onSelect()
        }
        .contextMenu {
            Button("在当前窗口打开") { self.onOpen() }
            Button("右侧分屏打开") { self.onOpenSplit() }
            Divider()
            Button("删除", role: .destructive) { self.onDelete() }
        }
    }
}
