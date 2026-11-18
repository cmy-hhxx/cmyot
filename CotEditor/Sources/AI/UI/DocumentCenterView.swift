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
    
    private var liveDocsByID: [String: Document] = [:]
    
    func liveDocument(for id: String) -> Document? {
        
        self.liveDocsByID[id]
    }
    
    
    func refresh() {
        
        let orderedOpenDocs = Self.collectOpenDocuments()
        var dbByCanonicalKey: [String: StoredDocumentRecord] = [:]
        for record in CotLocalDatabase.shared.documents {
            let key = Self.canonicalKey(filePath: record.filePath, rawID: record.id)
            if dbByCanonicalKey[key] == nil {
                dbByCanonicalKey[key] = record
            }
        }
        
        var liveByKey: [String: Document] = [:]
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
            let fallbackID = filePath ?? (doc.databaseDocumentID.hasPrefix("doc:") ? doc.databaseDocumentID : "doc:\(doc.databaseDocumentID)")
            
            merged.append(ManagedDocumentItem(
                id: key,
                dbRecordID: dbMatch?.id ?? fallbackID,
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
                    id: fallbackID,
                    title: doc.displayName,
                    filePath: filePath,
                    syntax: doc.syntaxName,
                    content: content,
                    highlightsJSON: "[]",
                    updatedAt: modifiedDate
                )
            ))
        }
        
        for record in CotLocalDatabase.shared.documents where !record.id.hasPrefix("weekly:") {
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
    
    
    private static func collectOpenDocuments() -> [Document] {
        
        var orderedOpenDocs: [Document] = []
        var seenPointers = Set<ObjectIdentifier>()
        
        for window in NSApp.orderedWindows {
            guard let docVC = (window.windowController as? DocumentWindowController)?.documentViewController else { continue }
            for pane in docVC.editorViewControllers {
                for tab in pane.tabs {
                    let doc = tab.document
                    if seenPointers.insert(ObjectIdentifier(doc)).inserted {
                        orderedOpenDocs.append(doc)
                    }
                }
            }
        }
        for case let doc as Document in NSDocumentController.shared.documents where seenPointers.insert(ObjectIdentifier(doc)).inserted {
            orderedOpenDocs.append(doc)
        }
        return orderedOpenDocs
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
    var onOpenDocument: ((Document?, StoredDocumentRecord?) -> Void)?
    var onDeleteDocument: ((DocumentCenterState.ManagedDocumentItem) -> Void)?
    var onCreateNewDocument: (() -> Void)?
    var onDismiss: (() -> Void)?
    
    @State private var db = CotLocalDatabase.shared
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @State private var copiedFlag = false
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    
    var body: some View {
        
        let displayedItems = self.filteredItems
        let activeItem = self.selectedItem(in: displayedItems)
        
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                self.sidebar(items: displayedItems, activeItem: activeItem)
                    .frame(width: 268)
                
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 1)
                
                Group {
                    if let item = activeItem {
                        self.detailView(for: item, displayedItems: displayedItems)
                    } else {
                        self.emptyView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            if let toastMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    Text(toastMessage)
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            self.state.refresh()
        }
        .onChange(of: self.db.documents) { _, _ in
            withAnimation(.snappy(duration: 0.22)) {
                self.state.refresh()
            }
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
    
    
    private func selectedItem(in items: [DocumentCenterState.ManagedDocumentItem]) -> DocumentCenterState.ManagedDocumentItem? {
        
        guard let selectedID = self.state.selectedID else { return items.first }
        return items.first(where: { $0.id == selectedID }) ?? items.first
    }
    
    
    // MARK: Sidebar
    
    private func sidebar(
        items: [DocumentCenterState.ManagedDocumentItem],
        activeItem: DocumentCenterState.ManagedDocumentItem?
    ) -> some View {
        
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(nsImage: WorkspaceCenterIcons.documentCenterIcon(isActive: false, size: NSSize(width: 15, height: 15)))
                        .renderingMode(.template)
                        .foregroundStyle(.secondary)
                    
                    Text("文档中心")
                        .font(.system(size: 13.5, weight: .semibold))
                    
                    Text("\(items.count)")
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
                        .pointerStyle(.link)
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
                        .pointerStyle(.link)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)
            
            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 1)
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(items) { item in
                        DocumentSidebarRow(
                            item: item,
                            isSelected: activeItem?.id == item.id,
                            statusColor: self.statusColor(for: item),
                            onSelect: {
                                self.isRenaming = false
                                self.state.selectedID = item.id
                            },
                            onOpen: {
                                self.open(item: item)
                            },
                            onDelete: {
                                self.delete(item: item, in: items)
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
    
    private func detailView(
        for item: DocumentCenterState.ManagedDocumentItem,
        displayedItems: [DocumentCenterState.ManagedDocumentItem]
    ) -> some View {
        
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
                    .pointerStyle(.link)
                    Button("取消") {
                        self.isRenaming = false
                    }
                    .controlSize(.small)
                    .pointerStyle(.link)
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
                    .pointerStyle(.link)
                    .help("重命名")
                    
                    Text("\(item.characterCount) 字")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
                
                HStack(spacing: 6) {
                    Button {
                        self.open(item: item)
                    } label: {
                        Label("打开", systemImage: "macwindow")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .pointerStyle(.link)
                    
                    Button(self.copiedFlag ? "已拷贝 ✓" : "拷贝") {
                        let pboard = NSPasteboard.general
                        pboard.clearContents()
                        pboard.setString(item.content, forType: .string)
                        self.copiedFlag = true
                        self.showToast("已拷贝「\(item.title)」")
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            self.copiedFlag = false
                        }
                    }
                    .controlSize(.small)
                    .pointerStyle(.link)
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
                let preview = item.content.count > 6_000
                    ? String(item.content.prefix(6_000)) + "\n\n……（仅预览前 6,000 字，点击上方「打开」查看全部）"
                    : (item.content.isEmpty ? "（空文档）" : item.content)
                
                Text(preview)
                    .font(.system(size: 13))
                    .lineSpacing(3.5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .id(item.id)
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
                    .pointerStyle(.link)
                }
                if let onCreateNewDocument = self.onCreateNewDocument {
                    Button("新建文档") {
                        onCreateNewDocument()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .pointerStyle(.link)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    
    // MARK: Actions
    
    private func open(item: DocumentCenterState.ManagedDocumentItem) {
        
        let liveDoc = self.state.liveDocument(for: item.id)
        if let onOpenDocument = self.onOpenDocument {
            onOpenDocument(liveDoc, item.storedRecord)
        } else if let liveDoc {
            liveDoc.makeWindowControllers()
            liveDoc.showWindows()
        } else if let path = item.filePath, FileManager.default.fileExists(atPath: path) {
            NSDocumentController.shared.openDocument(withContentsOf: URL(filePath: path), display: true) { _, _, _ in }
        }
    }
    
    
    private func delete(item: DocumentCenterState.ManagedDocumentItem, in list: [DocumentCenterState.ManagedDocumentItem]) {
        
        withAnimation(.snappy(duration: 0.22)) {
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
        }
        self.showToast("已删除「\(item.title)」")
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
                self.showToast("已重命名为「\(newName)」")
            } catch {
                self.showToast("重命名失败：\(error.localizedDescription)")
            }
        } else if let recordID = item.dbRecordID, item.filePath == nil {
            self.db.renameDocument(oldID: recordID, newID: recordID, newTitle: trimmed, newFilePath: nil)
            self.showToast("已重命名为「\(trimmed)」")
        }
        self.isRenaming = false
        self.state.refresh()
    }
    
    
    private func showToast(_ message: String) {
        
        self.toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.16)) {
            self.toastMessage = message
        }
        self.toastTask = Task {
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) {
                self.toastMessage = nil
            }
        }
    }
}


private struct DocumentSidebarRow: View {
    
    let item: DocumentCenterState.ManagedDocumentItem
    let isSelected: Bool
    let statusColor: Color
    var onSelect: () -> Void
    var onOpen: () -> Void
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
                            self.isTrashHovered ? Color.red.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                        .scaleEffect(self.isTrashHovered ? 1.08 : 1.0)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        self.isTrashHovered = hovering
                    }
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
        .pointerStyle(.link)
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
            Divider()
            Button("删除", role: .destructive) { self.onDelete() }
        }
    }
}
