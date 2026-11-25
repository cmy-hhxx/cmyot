//
//  DocumentCenterStarMapView.swift
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
import Combine
import SwiftUI

// MARK: - Star-Map Document Center (星图全景 · 语义关联 · 全文搜索 · 空格预览 · 漏斗分片整理)

struct DocumentCenterView: View {
    
    @Bindable var state: DocumentCenterState
    var onOpenDocument: ((Document?, StoredDocumentRecord?) -> Void)?
    var onOpenAllDocuments: (([DocumentCenterState.ManagedDocumentItem]) -> Void)?
    var onDeleteDocument: ((DocumentCenterState.ManagedDocumentItem) -> Void)?
    var onCreateNewDocument: (() -> Void)?
    var onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.registerWorkspaceCenterEscPop) private var registerEscPop
    @State private var db = CotLocalDatabase.shared
    @State private var focusedClusterID: String?
    @State private var quickLookItemID: String?
    @State private var panRequestToken = 0
    @State private var isSearchHUDCollapsed = false
    @FocusState private var isSearchFocused: Bool
    
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @FocusState private var isRenameFieldFocused: Bool
    @State private var isCreatingGroup = false
    @State private var newGroupDraft = ""
    @FocusState private var isNewGroupFieldFocused: Bool
    @State private var pendingAssignAfterGroupCreate: DocumentCenterState.ManagedDocumentItem?
    @State private var renamingGroupName: String?
    @State private var groupRenameDraft = ""
    @FocusState private var isGroupRenameFocused: Bool
    @State private var copiedFlag = false
    @State private var searchDraft = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var organizeTask: Task<Void, Never>?
    @State private var keyMonitor: Any?
    
    
    var body: some View {
        let displayedItems = self.state.displayedItems
        let activeItem = self.selectedItem(in: displayedItems)
        let tokens = DashPalette.editorialTokens(isDark: self.colorScheme == .dark)
        let clusters = self.state.buildStarMapClusters(tokens: tokens)
        let hasQuery = !self.state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let quickLookItem = self.quickLookItemID.flatMap { id in
            displayedItems.first(where: { $0.id == id }) ?? self.state.items.first(where: { $0.id == id })
        }
        
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                self.topBar(tokens: tokens, clusters: clusters)
                Rectangle().fill(tokens.hairline).frame(height: 1)
                
                if self.isCreatingGroup {
                    self.inlineGroupCreatorBar(tokens: tokens)
                    Rectangle().fill(tokens.hairline).frame(height: 1)
                }
                if let renamingGroup = self.renamingGroupName {
                    self.inlineGroupRenamerBar(oldName: renamingGroup, tokens: tokens)
                    Rectangle().fill(tokens.hairline).frame(height: 1)
                }
                
                self.canvasStage(
                    displayedItems: displayedItems,
                    activeItem: activeItem,
                    clusters: clusters,
                    hasQuery: hasQuery,
                    showingQuickLook: quickLookItem != nil,
                    tokens: tokens
                )
            }
            .background(tokens.canvasTop)
            
            if let qItem = quickLookItem {
                self.quickLookOverlay(qItem: qItem, displayedItems: displayedItems, tokens: tokens)
            }
            
            if let toastMessage = self.toastMessage {
                self.toastPill(message: toastMessage, tokens: tokens)
            }
        }
        .onAppear {
            self.state.refresh()
            self.searchDraft = self.state.searchText
            self.installKeyboardMonitor()
            self.registerEscPop? { self.handleEscapePop() }
        }
        .onDisappear {
            self.removeKeyboardMonitor()
            self.searchDebounceTask?.cancel()
            self.organizeTask?.cancel()
            self.registerEscPop?(nil)
        }
        .onChange(of: self.db.documents.count) { _, _ in self.state.refresh() }
        .onChange(of: self.db.trashedDocuments.count) { _, _ in self.state.refresh() }
        .onReceive(
            NotificationCenter.default.publisher(for: ScheduledAIDocumentOrganizer.didCompleteOrganizeNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            self.state.refresh()
        }
        .onChange(of: self.searchDraft) { _, newValue in
            self.scheduleSearchUpdate(newValue)
        }
        .onChange(of: self.state.searchText) { _, newValue in
            if self.searchDraft != newValue { self.searchDraft = newValue }
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.isSearchHUDCollapsed = false
            }
        }
    }
    
    
    // MARK: Star-Map Stage & QuickLook
    
    private func canvasStage(
        displayedItems: [DocumentCenterState.ManagedDocumentItem],
        activeItem: DocumentCenterState.ManagedDocumentItem?,
        clusters: [StarMapClusterNode],
        hasQuery: Bool,
        showingQuickLook: Bool,
        tokens: StudioColorTokens
    ) -> some View {
        let visibleIDs = Set(displayedItems.map(\.id))
        let visibleRelations = self.state.relations.filter {
            visibleIDs.contains($0.sourceID) && visibleIDs.contains($0.targetID)
        }
        
        return ZStack(alignment: .topTrailing) {
            if clusters.isEmpty {
                self.emptyStarMapState(tokens: tokens, hasQuery: hasQuery)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ConstellationStarMapView(
                    hubTitle: self.state.sidebarFilter == .trash ? "废纸篓" : "文档星图",
                    hubSubtitle: "\(displayedItems.count) 篇",
                    clusters: clusters,
                    relations: self.state.sidebarFilter == .trash ? [] : visibleRelations,
                    selectedLeafID: activeItem?.id,
                    focusedClusterID: self.focusedClusterID,
                    searchQuery: self.state.searchText,
                    panRequestToken: self.panRequestToken,
                    onSelectLeaf: { leafID in
                        self.isRenaming = false
                        self.state.selectedID = leafID
                    },
                    onDoubleClickLeaf: { leafID in
                        self.state.selectedID = leafID
                        guard let target = displayedItems.first(where: { $0.id == leafID }) else { return }
                        if target.isTrashed {
                            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                                self.quickLookItemID = target.id
                            }
                        } else {
                            self.open(item: target)
                        }
                    },
                    onToggleCluster: { clusterID in
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)) {
                            if self.state.collapsedClusterIDs.contains(clusterID) {
                                self.state.collapsedClusterIDs.remove(clusterID)
                                self.focusedClusterID = clusterID
                            } else {
                                self.state.collapsedClusterIDs.insert(clusterID)
                                if self.focusedClusterID == clusterID {
                                    self.focusedClusterID = nil
                                }
                            }
                        }
                    },
                    clusterContextMenu: { cluster in
                        self.clusterContextMenu(cluster: cluster, allItems: displayedItems)
                    },
                    leafContextMenu: { leaf in
                        if let target = displayedItems.first(where: { $0.id == leaf.id }) {
                            self.itemContextMenu(item: target, allItems: displayedItems)
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            if hasQuery {
                StarMapSearchResultsHUD(
                    hits: self.state.searchHits,
                    selectedID: activeItem?.id,
                    isCollapsed: self.isSearchHUDCollapsed,
                    tokens: tokens,
                    onToggleCollapse: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            self.isSearchHUDCollapsed.toggle()
                        }
                    },
                    onSelectHit: { hitID in
                        self.unfocusSearchField()
                        self.state.selectedID = hitID
                        self.panRequestToken &+= 1
                    },
                    onPreviewHit: { hitID in
                        self.unfocusSearchField()
                        self.state.selectedID = hitID
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                            self.quickLookItemID = hitID
                        }
                    },
                    onOpenHit: { hitID in
                        if let target = displayedItems.first(where: { $0.id == hitID }) ?? self.state.items.first(where: { $0.id == hitID }) {
                            self.open(item: target)
                        }
                    }
                )
                .padding(16)
            }
            
            if !showingQuickLook, let activeItem {
                VStack {
                    Spacer()
                    self.bottomSelectionCapsule(item: activeItem, allItems: displayedItems, tokens: tokens)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    
    private func quickLookOverlay(
        qItem: DocumentCenterState.ManagedDocumentItem,
        displayedItems: [DocumentCenterState.ManagedDocumentItem],
        tokens: StudioColorTokens
    ) -> some View {
        let navList = self.keyboardNavigationItems(displayedItems: displayedItems)
        let curIdx = navList.firstIndex(where: { $0.id == qItem.id }) ?? 0
        let canPrev = navList.count > 1 && curIdx > 0
        let canNext = navList.count > 1 && curIdx + 1 < navList.count
        let related = self.state.relatedNodes(for: qItem.id, in: self.state.items)
        let highlightTerms = StarMapSearchEngine.parseTerms(self.state.searchText)
        
        return StarMapQuickLookOverlay(
            title: qItem.title,
            subtitle: "\(qItem.groupName.isEmpty ? "未分组" : qItem.groupName) · \(qItem.compactCharCount) · \(qItem.relativeTimeText)",
            canStepPrevious: canPrev,
            canStepNext: canNext,
            onPrevious: {
                guard canPrev else { return }
                let prev = navList[curIdx - 1]
                self.state.selectedID = prev.id
                self.quickLookItemID = prev.id
            },
            onNext: {
                guard canNext else { return }
                let next = navList[curIdx + 1]
                self.state.selectedID = next.id
                self.quickLookItemID = next.id
            },
            onClose: {
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                    self.quickLookItemID = nil
                }
            },
            headerActions: {
                HStack(spacing: 6) {
                    if qItem.isTrashed {
                        Button("恢复") {
                            self.restore(item: qItem)
                            self.quickLookItemID = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Button("打开") {
                            self.quickLookItemID = nil
                            self.open(item: qItem)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    Button(self.copiedFlag ? "已复制" : "复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(qItem.content, forType: .string)
                        self.copiedFlag = true
                        self.showToast("已复制")
                        Task {
                            try? await Task.sleep(for: .seconds(1.4))
                            self.copiedFlag = false
                        }
                    }
                    .controlSize(.small)
                }
            },
            bodyContent: {
                VStack(spacing: 0) {
                    if !related.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Text("关联")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(tokens.primaryInk.opacity(0.55))
                                ForEach(related.prefix(5), id: \.item.id) { entry in
                                    Button {
                                        self.state.selectedID = entry.item.id
                                        self.quickLookItemID = entry.item.id
                                        self.panRequestToken &+= 1
                                    } label: {
                                        Text("\(entry.item.title) · \(entry.reason)")
                                            .font(.system(size: 10.5, weight: .medium))
                                            .foregroundStyle(tokens.accentText)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(tokens.positivePillBg, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .pointerStyle(.link)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                        }
                        .background(tokens.canvasBottom)
                        Rectangle().fill(tokens.hairline).frame(height: 1)
                    }
                    CenterPreviewTextView(text: qItem.previewText, highlightTerms: highlightTerms)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        )
    }
    
    
    // MARK: Top Bar
    
    private func topBar(tokens: StudioColorTokens, clusters: [StarMapClusterNode]) -> some View {
        HStack(spacing: 8) {
            if let onDismiss = self.onDismiss {
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(tokens.primaryInk.opacity(0.84))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            
            Text("文档星图")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tokens.primaryInk)
            
            self.scopeFilterBar(tokens: tokens)
            self.groupAndTimeMenus(tokens: tokens, clusters: clusters)
            
            Spacer(minLength: 6)
            
            self.searchField(tokens: tokens)
            self.organizeAndCreateControls(tokens: tokens)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(tokens.canvasTop)
    }
    
    
    private func scopeFilterBar(tokens: StudioColorTokens) -> some View {
        HStack(spacing: 2) {
            self.scopeChip(title: "全部 \(self.state.items.count)", isActive: self.state.sidebarFilter == .all, tokens: tokens) {
                self.focusedClusterID = nil
                self.state.sidebarFilter = .all
            }
            self.scopeChip(title: "打开中 \(self.state.openCount)", isActive: self.state.sidebarFilter == .openNow, tokens: tokens) {
                self.focusedClusterID = nil
                self.state.sidebarFilter = .openNow
            }
            if !self.state.trashedItems.isEmpty || self.state.sidebarFilter == .trash {
                self.scopeChip(title: "废纸篓 \(self.state.trashedItems.count)", isActive: self.state.sidebarFilter == .trash, tokens: tokens) {
                    self.focusedClusterID = nil
                    self.state.sidebarFilter = .trash
                }
            }
        }
        .padding(2.5)
        .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    
    
    @ViewBuilder
    private func groupAndTimeMenus(tokens: StudioColorTokens, clusters: [StarMapClusterNode]) -> some View {
        let groupNames: [String] = {
            var ordered = self.db.documentGroups
            for key in self.state.groupCounts.keys.sorted() where !ordered.contains(key) {
                ordered.append(key)
            }
            return ordered
        }()
        let allCollapsed = clusters.isEmpty || clusters.allSatisfy(\.isCollapsed)
        
        if !groupNames.isEmpty {
            Menu {
                Button("全部分组") {
                    self.focusedClusterID = nil
                    self.state.sidebarFilter = .all
                }
                Divider()
                ForEach(groupNames, id: \.self) { groupName in
                    Button("\(groupName)（\(self.state.groupCounts[groupName] ?? 0)）") {
                        self.focusedClusterID = "group:\(groupName)"
                        self.state.sidebarFilter = .group(groupName)
                    }
                }
                if self.state.ungroupedCount > 0 {
                    Button("未分组（\(self.state.ungroupedCount)）") {
                        self.focusedClusterID = "__ungrouped__"
                        self.state.sidebarFilter = .ungrouped
                    }
                }
                Divider()
                Button("新建分组") {
                    self.newGroupDraft = ""
                    self.pendingAssignAfterGroupCreate = nil
                    self.isCreatingGroup = true
                    DispatchQueue.main.async { self.isNewGroupFieldFocused = true }
                }
            } label: {
                let activeLabel: String = switch self.state.sidebarFilter {
                    case .group(let name): name
                    case .ungrouped: "未分组"
                    default: "分组"
                }
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10.5, weight: .medium))
                    Text(activeLabel)
                        .font(.system(size: 11.5, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(tokens.primaryInk.opacity(0.5))
                }
                .foregroundStyle(tokens.primaryInk.opacity(0.84))
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .pointerStyle(.link)
        }
        
        Menu {
            ForEach(DocumentCenterState.TimeHorizon.allCases, id: \.self) { horizon in
                Button {
                    self.state.timeHorizon = horizon
                } label: {
                    if self.state.timeHorizon == horizon {
                        Label(horizon.rawValue, systemImage: "checkmark")
                    } else {
                        Text(horizon.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(self.state.timeHorizon == .all ? tokens.primaryInk.opacity(0.60) : tokens.accentText)
                Text(self.state.timeHorizon.rawValue)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(self.state.timeHorizon == .all ? tokens.primaryInk.opacity(0.84) : tokens.accentText)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tokens.primaryInk.opacity(0.45))
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                self.state.timeHorizon == .all ? tokens.inset : tokens.accent.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .pointerStyle(.link)
        
        if !clusters.isEmpty {
            Button {
                let ids = clusters.map(\.id)
                withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                    if allCollapsed {
                        self.state.expandAllClusters(ids)
                    } else {
                        self.focusedClusterID = nil
                        self.state.collapseAllClusters(ids)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: allCollapsed ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(allCollapsed ? "展开全部" : "全部折叠")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(tokens.primaryInk.opacity(0.80))
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
    }
    
    
    private func searchField(tokens: StudioColorTokens) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(self.isSearchFocused ? tokens.accent : tokens.primaryInk.opacity(0.45))
            TextField("搜索文档", text: self.$searchDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused(self.$isSearchFocused)
                .frame(minWidth: 160, maxWidth: 230)
                .onSubmit {
                    self.searchDebounceTask?.cancel()
                    let query = self.searchDraft
                    self.unfocusSearchField()
                    self.searchDebounceTask = Task {
                        guard await self.state.applySearch(query), let firstHit = self.state.searchHits.first else { return }
                        self.state.selectedID = firstHit.id
                        self.panRequestToken &+= 1
                    }
                }
            if !self.searchDraft.isEmpty {
                Text("\(self.state.searchHits.count) 篇")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(tokens.accentText)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 1.5)
                    .background(tokens.positivePillBg, in: Capsule())
                
                Button {
                    self.searchDebounceTask?.cancel()
                    self.searchDraft = ""
                    self.state.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(tokens.primaryInk.opacity(0.42))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(self.isSearchFocused ? tokens.accent.opacity(0.65) : tokens.hairline, lineWidth: self.isSearchFocused ? 1.1 : 0.75)
        )
    }
    
    
    @ViewBuilder
    private func organizeAndCreateControls(tokens: StudioColorTokens) -> some View {
        if self.state.sidebarFilter == .trash && !self.state.displayedItems.isEmpty {
            Button("清空废纸篓") {
                self.confirmEmptyTrash()
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.red)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
        
        if self.state.isAgentOrganizing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(self.state.agentOrganizeProgressText)
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(tokens.accentText)
                Button("取消") {
                    self.cancelAgentOrganize()
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(tokens.primaryInk.opacity(0.65))
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(tokens.positivePillBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            if let summary = self.state.agentOrganizeSummary {
                HStack(spacing: 6) {
                    Text(summary)
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(tokens.accentText)
                    if !self.state.lastOrganizeUndoSnapshot.isEmpty {
                        Button("撤销") {
                            self.undoAgentOrganize()
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tokens.primaryInk)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(tokens.card, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                    Button {
                        self.state.agentOrganizeSummary = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(tokens.primaryInk.opacity(0.48))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(tokens.positivePillBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            
            Button {
                self.runAgentAutoOrganize()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("一键整理")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(tokens.accentText)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(tokens.positivePillBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(tokens.accent.opacity(0.28), lineWidth: 0.75))
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .disabled(self.state.items.isEmpty)
            .opacity(self.state.items.isEmpty ? 0.45 : 1)
        }
        
        if let onCreateNewDocument = self.onCreateNewDocument {
            Button(action: onCreateNewDocument) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10.5, weight: .bold))
                    Text("新建")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(tokens.onAccentInk)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
    }
    
    
    private func scopeChip(title: String, isActive: Bool, tokens: StudioColorTokens, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium).monospacedDigit())
                .foregroundStyle(isActive ? tokens.primaryInk : tokens.primaryInk.opacity(0.60))
                .padding(.horizontal, 8)
                .frame(height: 23)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(isActive ? tokens.card : Color.clear))
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    private func inlineGroupCreatorBar(tokens: StudioColorTokens) -> some View {
        HStack(spacing: 8) {
            Text("新建分组")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.primaryInk.opacity(0.70))
            TextField("分组名", text: self.$newGroupDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused(self.$isNewGroupFieldFocused)
                .padding(.horizontal, 8)
                .frame(width: 190, height: 26)
                .background(tokens.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onSubmit { self.commitCreateGroup() }
                .onExitCommand {
                    self.isCreatingGroup = false
                    self.pendingAssignAfterGroupCreate = nil
                }
            Button("确定") { self.commitCreateGroup() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button("取消") {
                self.isCreatingGroup = false
                self.pendingAssignAfterGroupCreate = nil
            }
            .controlSize(.small)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(tokens.canvasBottom)
    }
    
    
    private func inlineGroupRenamerBar(oldName: String, tokens: StudioColorTokens) -> some View {
        HStack(spacing: 8) {
            Text("重命名「\(oldName)」")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.primaryInk.opacity(0.70))
            TextField("新分组名", text: self.$groupRenameDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused(self.$isGroupRenameFocused)
                .padding(.horizontal, 8)
                .frame(width: 190, height: 26)
                .background(tokens.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onSubmit { self.commitGroupRename(oldName: oldName) }
                .onExitCommand { self.renamingGroupName = nil }
            Button("保存") { self.commitGroupRename(oldName: oldName) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button("取消") { self.renamingGroupName = nil }
                .controlSize(.small)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(tokens.canvasBottom)
    }
    
    
    private func emptyStarMapState(tokens: StudioColorTokens, hasQuery: Bool) -> some View {
        VStack(spacing: 10) {
            Text(hasQuery ? "未检索到匹配文档" : (self.state.sidebarFilter == .trash ? "废纸篓为空" : "暂无文档"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tokens.primaryInk.opacity(0.55))
            if hasQuery {
                Button("清除搜索") {
                    self.searchDraft = ""
                    self.state.searchText = ""
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.accentText)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(tokens.accent.opacity(0.12), in: Capsule())
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .background(tokens.canvasTop)
    }
    
    
    private func toastPill(message: String, tokens: StudioColorTokens) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tokens.accent).frame(width: 6, height: 6)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.primaryInk)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(tokens.card, in: Capsule())
        .overlay(Capsule().strokeBorder(tokens.hairlineStrong, lineWidth: 0.8))
        .padding(.bottom, 18)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
    
    
    // MARK: Bottom Selection & Relationships Capsule
    
    private func bottomSelectionCapsule(
        item: DocumentCenterState.ManagedDocumentItem,
        allItems: [DocumentCenterState.ManagedDocumentItem],
        tokens: StudioColorTokens
    ) -> some View {
        let related = item.isTrashed ? [] : self.state.relatedNodes(for: item.id, in: self.state.items)
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(item.isDirty ? Color.orange : tokens.accent)
                    .frame(width: 8, height: 8)
                
                if self.isRenaming {
                    self.inlineRenameRow(item: item, tokens: tokens)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tokens.primaryInk)
                            .lineLimit(1)
                        Text("\(item.groupName.isEmpty ? "未分组" : item.groupName) · \(item.compactCharCount) · \(item.relativeTimeText)")
                            .font(.system(size: 10.5, design: .rounded).monospacedDigit())
                            .foregroundStyle(tokens.primaryInk.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 8)
                self.capsuleActionButtons(item: item, allItems: allItems, tokens: tokens)
            }
            
            if !related.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("关联文档")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(tokens.primaryInk.opacity(0.55))
                        ForEach(related, id: \.item.id) { entry in
                            Button {
                                self.state.selectedID = entry.item.id
                                self.panRequestToken &+= 1
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "link")
                                        .font(.system(size: 9.5, weight: .semibold))
                                    Text("\(entry.item.title) · \(entry.reason)")
                                        .font(.system(size: 10.5, weight: .medium))
                                }
                                .foregroundStyle(tokens.accentText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(tokens.positivePillBg, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 660)
        .background(tokens.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tokens.hairlineStrong, lineWidth: 0.9))
        .shadow(color: tokens.cardShadow, radius: 10, y: 4)
        .padding(.horizontal, 24)
    }
    
    
    @ViewBuilder
    private func inlineRenameRow(item: DocumentCenterState.ManagedDocumentItem, tokens: StudioColorTokens) -> some View {
        TextField("文档标题", text: self.$renameDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .focused(self.$isRenameFieldFocused)
            .padding(.horizontal, 8)
            .frame(width: 220, height: 26)
            .background(tokens.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onSubmit { self.commitRename(for: item) }
            .onExitCommand { self.isRenaming = false }
        Button("保存") { self.commitRename(for: item) }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
        Button("取消") { self.isRenaming = false }
            .controlSize(.small)
    }
    
    
    @ViewBuilder
    private func capsuleActionButtons(
        item: DocumentCenterState.ManagedDocumentItem,
        allItems: [DocumentCenterState.ManagedDocumentItem],
        tokens: StudioColorTokens
    ) -> some View {
        Button {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                self.quickLookItemID = item.id
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "eye")
                    .font(.system(size: 10.5, weight: .medium))
                Text("预览")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(tokens.primaryInk.opacity(0.84))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(tokens.inset, in: Capsule())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        
        if item.isTrashed {
            Button {
                self.restore(item: item)
            } label: {
                Text("恢复")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(tokens.onAccentInk)
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .background(tokens.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            Button {
                self.permanentlyDelete(item: item)
            } label: {
                Text("彻底删除")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.red.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        } else {
            Button {
                self.open(item: item)
            } label: {
                Text("打开")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(tokens.onAccentInk)
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .background(tokens.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            Menu {
                Button("未分组") { self.move(item: item, toGroup: "") }
                if !self.db.documentGroups.isEmpty {
                    Divider()
                    ForEach(self.db.documentGroups, id: \.self) { group in
                        Button(group) { self.move(item: item, toGroup: group) }
                    }
                }
                Divider()
                Button("新建分组") {
                    self.pendingAssignAfterGroupCreate = item
                    self.newGroupDraft = ""
                    self.isCreatingGroup = true
                    DispatchQueue.main.async { self.isNewGroupFieldFocused = true }
                }
                Divider()
                Button("重命名") {
                    self.renameDraft = item.title
                    self.isRenaming = true
                    DispatchQueue.main.async { self.isRenameFieldFocused = true }
                }
                Button("移入废纸篓", role: .destructive) {
                    self.delete(item: item, in: allItems)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tokens.primaryInk.opacity(0.70))
                    .frame(width: 26, height: 26)
                    .background(tokens.inset, in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .pointerStyle(.link)
        }
    }
    
    
    // MARK: Context Menus
    
    @ViewBuilder
    private func clusterContextMenu(
        cluster: StarMapClusterNode,
        allItems: [DocumentCenterState.ManagedDocumentItem]
    ) -> some View {
        Button(self.focusedClusterID == cluster.id ? "取消分组聚焦" : "聚焦此分组") {
            self.focusedClusterID = (self.focusedClusterID == cluster.id) ? nil : cluster.id
        }
        Button(cluster.isCollapsed ? "展开此分组" : "折叠此分组") {
            if self.state.collapsedClusterIDs.contains(cluster.id) {
                self.state.collapsedClusterIDs.remove(cluster.id)
            } else {
                self.state.collapsedClusterIDs.insert(cluster.id)
            }
        }
        if cluster.id.hasPrefix("group:") {
            let groupName = String(cluster.id.dropFirst(6))
            Button("打开全部分组文档") {
                let groupItems = self.state.items.filter { $0.groupName == groupName }
                self.openAll(items: groupItems)
            }
            Button("重命名分组") {
                self.groupRenameDraft = groupName
                self.renamingGroupName = groupName
                DispatchQueue.main.async { self.isGroupRenameFocused = true }
            }
            Divider()
            Button("解散分组", role: .destructive) {
                self.db.deleteDocumentGroup(named: groupName)
                if self.focusedClusterID == cluster.id { self.focusedClusterID = nil }
                if self.state.sidebarFilter == .group(groupName) { self.state.sidebarFilter = .all }
                self.state.refresh()
                self.showToast("已解散「\(groupName)」")
            }
        }
    }
    
    
    @ViewBuilder
    private func itemContextMenu(
        item: DocumentCenterState.ManagedDocumentItem,
        allItems: [DocumentCenterState.ManagedDocumentItem]
    ) -> some View {
        Button("空格预览") {
            self.state.selectedID = item.id
            self.quickLookItemID = item.id
        }
        if item.isTrashed {
            Button("恢复") { self.restore(item: item) }
            Divider()
            Button("彻底删除", role: .destructive) { self.permanentlyDelete(item: item) }
        } else {
            Button("在编辑器打开") { self.open(item: item) }
            Button("重命名") {
                self.state.selectedID = item.id
                self.renameDraft = item.title
                self.isRenaming = true
                DispatchQueue.main.async { self.isRenameFieldFocused = true }
            }
            Menu("移动到分组") {
                Button("未分组") { self.move(item: item, toGroup: "") }
                if !self.db.documentGroups.isEmpty {
                    Divider()
                    ForEach(self.db.documentGroups, id: \.self) { group in
                        Button(group) { self.move(item: item, toGroup: group) }
                    }
                }
                Divider()
                Button("新建分组") {
                    self.pendingAssignAfterGroupCreate = item
                    self.newGroupDraft = ""
                    self.isCreatingGroup = true
                    DispatchQueue.main.async { self.isNewGroupFieldFocused = true }
                }
            }
            Divider()
            Button("移入废纸篓", role: .destructive) {
                self.delete(item: item, in: allItems)
            }
        }
    }
    
    
    // MARK: Data-Funnel Sharded One-Click Auto-Organize
    
    private func runAgentAutoOrganize() {
        let snapshotItems = self.state.items
        guard !snapshotItems.isEmpty, !self.state.isAgentOrganizing else { return }
        
        self.organizeTask?.cancel()
        self.state.isAgentOrganizing = true
        self.state.agentOrganizeProgressText = "漏斗清洗 \(snapshotItems.count) 篇"
        self.state.agentOrganizeSummary = nil
        
        let existingGroups = self.db.documentGroups
        let funnelInputs: [OrganizeFunnelInput] = snapshotItems.map { item in
            OrganizeFunnelInput(
                id: item.id,
                dbRecordID: item.dbRecordID ?? item.id,
                title: item.title,
                filePath: item.filePath,
                syntax: item.syntax,
                currentGroup: item.groupName,
                content: item.content,
                updatedAt: item.updatedAt,
                isOpenNow: item.isOpenNow,
                isUntitled: DocumentCenterAgentOrganizer.isGenericUntitled(item.title, hasFilePath: item.filePath != nil)
            )
        }
        let itemsByID = Dictionary(uniqueKeysWithValues: snapshotItems.map { ($0.id, $0) })
        
        self.organizeTask = Task {
            let fullPlan = await DocumentOrganizeFunnel.runFullPipeline(
                items: funnelInputs,
                existingGroups: existingGroups,
                allowRemoteAI: true,
                onProgress: { progress in
                    self.state.agentOrganizeProgressText = progress.statusText
                }
            )
            guard !Task.isCancelled else {
                self.state.isAgentOrganizing = false
                return
            }
            
            let stats = self.applyOrganizeFullPlan(fullPlan, itemsByID: itemsByID)
            self.state.isAgentOrganizing = false
            self.state.refresh()
            
            var summaryParts: [String] = []
            if stats.deletedJunk > 0 { summaryParts.append("删 \(stats.deletedJunk) 无效") }
            if stats.mergedDuplicates > 0 { summaryParts.append("合 \(stats.mergedDuplicates) 重复") }
            if stats.classified > 0 { summaryParts.append("整理 \(stats.classified) 篇") }
            if stats.groupCount > 0 { summaryParts.append("\(stats.groupCount) 组") }
            
            if summaryParts.isEmpty {
                self.showToast("星图已整齐，无需调整")
            } else {
                self.state.agentOrganizeSummary = summaryParts.joined(separator: " · ")
            }
        }
    }
    
    
    private func applyOrganizeFullPlan(
        _ fullPlan: OrganizeFullPlan,
        itemsByID: [String: DocumentCenterState.ManagedDocumentItem]
    ) -> (deletedJunk: Int, mergedDuplicates: Int, classified: Int, groupCount: Int) {
        var undoEntries: [DocumentCenterState.OrganizeUndoEntry] = []
        var existingGroupSet = Set(self.db.documentGroups)
        var createdGroups: [String] = []
        var touchedGroups = Set<String>()
        var deletedJunk = 0
        var mergedDuplicates = 0
        var classifiedCount = 0
        
        let mergedByPrimaryID = Dictionary(uniqueKeysWithValues: fullPlan.funnel.mergeClusters.map { ($0.primary.id, $0) })
        
        self.db.withTransaction {
            // 1. Delete meaningless test / empty / garbled documents directly.
            for decision in fullPlan.funnel.junkToDelete {
                guard let item = itemsByID[decision.item.id] else { continue }
                let recordID = item.dbRecordID ?? item.id
                undoEntries.append(DocumentCenterState.OrganizeUndoEntry(
                    kind: .deleted,
                    itemID: item.id,
                    dbRecordID: recordID,
                    filePath: item.filePath,
                    previousGroup: item.groupName,
                    previousTitle: item.title,
                    titleWasChanged: false,
                    syntax: item.syntax,
                    content: item.content
                ))
                self.db.permanentlyDeleteDocument(id: recordID, filePath: item.filePath)
                self.closeUntitledLiveDocumentIfPresent(canonicalID: item.id)
                deletedJunk += 1
            }
            
            // 2. Merge duplicate documents losslessly into their canonical primary.
            for cluster in fullPlan.funnel.mergeClusters {
                guard let primaryItem = itemsByID[cluster.primary.id] else { continue }
                let primaryRecordID = primaryItem.dbRecordID ?? primaryItem.id
                undoEntries.append(DocumentCenterState.OrganizeUndoEntry(
                    kind: .mergedPrimary,
                    itemID: primaryItem.id,
                    dbRecordID: primaryRecordID,
                    filePath: primaryItem.filePath,
                    previousGroup: primaryItem.groupName,
                    previousTitle: primaryItem.title,
                    titleWasChanged: cluster.bestTitle != primaryItem.title,
                    syntax: primaryItem.syntax,
                    content: primaryItem.content
                ))
                
                if let liveDoc = self.state.liveDocument(for: primaryItem.id),
                   cluster.mergedContent != liveDoc.textStorage.string
                {
                    liveDoc.textStorage.replaceCharacters(
                        in: NSRange(location: 0, length: liveDoc.textStorage.length),
                        with: cluster.mergedContent
                    )
                    if liveDoc.fileURL == nil {
                        liveDoc.updateChangeCount(.changeCleared)
                    }
                }
                self.db.saveDocument(
                    id: primaryRecordID,
                    title: cluster.bestTitle,
                    filePath: primaryItem.filePath,
                    syntax: primaryItem.syntax,
                    content: cluster.mergedContent,
                    groupName: cluster.bestGroup
                )
                
                for dup in cluster.duplicates {
                    guard let dupItem = itemsByID[dup.id] else { continue }
                    let dupRecordID = dupItem.dbRecordID ?? dupItem.id
                    undoEntries.append(DocumentCenterState.OrganizeUndoEntry(
                        kind: .deleted,
                        itemID: dupItem.id,
                        dbRecordID: dupRecordID,
                        filePath: dupItem.filePath,
                        previousGroup: dupItem.groupName,
                        previousTitle: dupItem.title,
                        titleWasChanged: false,
                        syntax: dupItem.syntax,
                        content: dupItem.content
                    ))
                    self.db.permanentlyDeleteDocument(id: dupRecordID, filePath: dupItem.filePath)
                    self.closeUntitledLiveDocumentIfPresent(canonicalID: dupItem.id)
                    mergedDuplicates += 1
                }
            }
            
            // 3. Apply sharded classification & untitled renaming on clean survivors.
            for assignment in fullPlan.assignments {
                guard let item = itemsByID[assignment.id] else { continue }
                let mergedCluster = mergedByPrimaryID[assignment.id]
                let effectiveTitle = mergedCluster?.bestTitle ?? item.title
                let effectiveGroup = mergedCluster?.bestGroup ?? item.groupName
                let effectiveContent = mergedCluster?.mergedContent ?? item.content
                
                let targetGroup = assignment.group
                let wantsRename: String? = {
                    guard let suggested = assignment.suggestedTitle,
                          !suggested.isEmpty,
                          suggested != effectiveTitle,
                          DocumentCenterAgentOrganizer.isGenericUntitled(effectiveTitle, hasFilePath: item.filePath != nil)
                    else { return nil }
                    return suggested
                }()
                let groupChanged = (targetGroup != effectiveGroup)
                guard groupChanged || wantsRename != nil else { continue }
                
                let recordID = item.dbRecordID ?? item.id
                if mergedCluster == nil {
                    undoEntries.append(DocumentCenterState.OrganizeUndoEntry(
                        kind: .modified,
                        itemID: item.id,
                        dbRecordID: recordID,
                        filePath: item.filePath,
                        previousGroup: item.groupName,
                        previousTitle: item.title,
                        titleWasChanged: wantsRename != nil,
                        syntax: item.syntax,
                        content: item.content
                    ))
                }
                
                if groupChanged {
                    if !targetGroup.isEmpty, existingGroupSet.insert(targetGroup).inserted {
                        createdGroups.append(targetGroup)
                    }
                    self.db.assignDocumentGroup(
                        id: recordID,
                        filePath: item.filePath,
                        groupName: targetGroup,
                        fallbackTitle: wantsRename ?? effectiveTitle,
                        fallbackSyntax: item.syntax,
                        fallbackContent: effectiveContent,
                        reloadAfter: false
                    )
                    if !targetGroup.isEmpty { touchedGroups.insert(targetGroup) }
                }
                
                if let newTitle = wantsRename {
                    if let liveDoc = self.state.liveDocument(for: item.id) {
                        _ = try? WorkspaceOrganizer.renameDocument(liveDoc, to: newTitle, reloadAfter: false)
                    } else if item.filePath == nil {
                        self.db.renameDocument(
                            oldID: recordID,
                            oldFilePath: nil,
                            newID: recordID,
                            newTitle: newTitle,
                            newFilePath: nil,
                            reloadAfter: false
                        )
                    }
                }
                classifiedCount += 1
            }
        }
        
        if deletedJunk > 0 || mergedDuplicates > 0 || classifiedCount > 0 {
            self.db.reloadDocuments()
        }
        self.state.lastOrganizeUndoSnapshot = undoEntries
        self.state.lastOrganizeCreatedGroups = createdGroups
        return (deletedJunk, mergedDuplicates, classifiedCount, touchedGroups.count)
    }
    
    
    private func closeUntitledLiveDocumentIfPresent(canonicalID: String) {
        guard let liveDoc = self.state.liveDocument(for: canonicalID), liveDoc.fileURL == nil else { return }
        for window in NSApp.orderedWindows {
            guard let docVC = (window.windowController as? DocumentWindowController)?.documentViewController else { continue }
            for pane in docVC.editorViewControllers {
                if let tab = pane.tabs.first(where: { $0.document === liveDoc }) {
                    if pane.tabs.count > 1 {
                        _ = docVC.closeMergedTabSafely(tab, in: pane)
                    }
                    return
                }
            }
        }
    }
    
    
    private func cancelAgentOrganize() {
        self.organizeTask?.cancel()
        self.organizeTask = nil
        self.state.isAgentOrganizing = false
    }
    
    
    private func undoAgentOrganize() {
        let entries = self.state.lastOrganizeUndoSnapshot
        let createdGroups = self.state.lastOrganizeCreatedGroups
        guard !entries.isEmpty else { return }
        
        self.db.withTransaction {
            for entry in entries {
                switch entry.kind {
                    case .deleted:
                        self.db.saveDocument(
                            id: entry.dbRecordID,
                            title: entry.previousTitle,
                            filePath: entry.filePath,
                            syntax: entry.syntax,
                            content: entry.content,
                            groupName: entry.previousGroup
                        )
                    case .mergedPrimary:
                        if let liveDoc = self.state.liveDocument(for: entry.itemID) {
                            liveDoc.textStorage.replaceCharacters(
                                in: NSRange(location: 0, length: liveDoc.textStorage.length),
                                with: entry.content
                            )
                            if liveDoc.fileURL == nil {
                                liveDoc.updateChangeCount(.changeCleared)
                            }
                            if entry.titleWasChanged {
                                _ = try? WorkspaceOrganizer.renameDocument(liveDoc, to: entry.previousTitle, reloadAfter: false)
                            }
                        }
                        self.db.saveDocument(
                            id: entry.dbRecordID,
                            title: entry.previousTitle,
                            filePath: entry.filePath,
                            syntax: entry.syntax,
                            content: entry.content,
                            groupName: entry.previousGroup
                        )
                    case .modified:
                        self.db.assignDocumentGroup(
                            id: entry.dbRecordID,
                            filePath: entry.filePath,
                            groupName: entry.previousGroup,
                            fallbackTitle: entry.previousTitle,
                            fallbackSyntax: entry.syntax,
                            fallbackContent: entry.content,
                            reloadAfter: false
                        )
                        if entry.titleWasChanged {
                            if let liveDoc = self.state.liveDocument(for: entry.itemID) {
                                _ = try? WorkspaceOrganizer.renameDocument(liveDoc, to: entry.previousTitle, reloadAfter: false)
                            } else if entry.filePath == nil {
                                self.db.renameDocument(
                                    oldID: entry.dbRecordID,
                                    oldFilePath: nil,
                                    newID: entry.dbRecordID,
                                    newTitle: entry.previousTitle,
                                    newFilePath: nil,
                                    reloadAfter: false
                                )
                            }
                        }
                }
            }
            
            for group in createdGroups where !self.db.documents.contains(where: { $0.groupName == group }) {
                self.db.deleteDocumentGroup(named: group)
            }
        }
        self.db.reloadDocuments()
        
        self.state.lastOrganizeUndoSnapshot = []
        self.state.lastOrganizeCreatedGroups = []
        self.state.agentOrganizeSummary = nil
        self.state.sidebarFilter = .all
        self.state.refresh()
        self.showToast("已撤销整理")
    }
    
    
    // MARK: Selection, QuickLook & Keyboard Navigation
    
    private func scheduleSearchUpdate(_ newValue: String) {
        self.searchDebounceTask?.cancel()
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if !self.state.searchText.isEmpty { self.state.searchText = "" }
            return
        }
        self.searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(110))
            _ = await self.state.applySearch(newValue)
        }
    }
    
    
    private func selectedItem(in items: [DocumentCenterState.ManagedDocumentItem]) -> DocumentCenterState.ManagedDocumentItem? {
        if let id = self.state.selectedID, let match = items.first(where: { $0.id == id }) {
            return match
        }
        return items.first
    }
    
    
    private func keyboardNavigationItems(displayedItems: [DocumentCenterState.ManagedDocumentItem]) -> [DocumentCenterState.ManagedDocumentItem] {
        let hasQuery = !self.state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasQuery && !self.state.searchHits.isEmpty {
            let map = Dictionary(uniqueKeysWithValues: displayedItems.map { ($0.id, $0) })
            return self.state.searchHits.compactMap { map[$0.id] }
        }
        return displayedItems
    }
    
    
    private func unfocusSearchField() {
        self.isSearchFocused = false
        if let tv = NSApp.keyWindow?.firstResponder as? NSTextView, tv.isEditable {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
    
    
    private func handleEscapePop() -> Bool {
        if self.isRenaming {
            self.isRenaming = false
            return true
        }
        if self.quickLookItemID != nil {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                self.quickLookItemID = nil
            }
            return true
        }
        if self.isCreatingGroup {
            self.isCreatingGroup = false
            self.pendingAssignAfterGroupCreate = nil
            return true
        }
        if self.renamingGroupName != nil {
            self.renamingGroupName = nil
            return true
        }
        if !self.state.searchText.isEmpty {
            self.state.searchText = ""
            return true
        }
        if self.focusedClusterID != nil {
            self.focusedClusterID = nil
            return true
        }
        return false
    }
    
    
    private func installKeyboardMonitor() {
        self.removeKeyboardMonitor()
        self.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "f" {
                self.quickLookItemID = nil
                self.isSearchFocused = true
                return nil
            }
            if let tv = (event.window ?? NSApp.keyWindow)?.firstResponder as? NSTextView, tv.isEditable {
                if event.keyCode == 125 && self.isSearchFocused {
                    self.unfocusSearchField()
                    return nil
                }
                return event
            }
            let navList = self.keyboardNavigationItems(displayedItems: self.state.displayedItems)
            guard !navList.isEmpty else { return event }
            
            switch event.keyCode {
                case 49:
                    if self.quickLookItemID != nil {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.15)) {
                            self.quickLookItemID = nil
                        }
                        return nil
                    }
                    if let active = self.selectedItem(in: navList) {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                            self.quickLookItemID = active.id
                        }
                        return nil
                    }
                case 123, 126:
                    self.stepSelection(by: -1, in: navList)
                    return nil
                case 124, 125:
                    self.stepSelection(by: 1, in: navList)
                    return nil
                case 36:
                    if let active = self.selectedItem(in: navList), !active.isTrashed {
                        self.quickLookItemID = nil
                        self.open(item: active)
                        return nil
                    }
                default:
                    break
            }
            return event
        }
    }
    
    
    private func removeKeyboardMonitor() {
        if let monitor = self.keyMonitor {
            NSEvent.removeMonitor(monitor)
            self.keyMonitor = nil
        }
    }
    
    
    private func stepSelection(by delta: Int, in list: [DocumentCenterState.ManagedDocumentItem]) {
        guard !list.isEmpty else { return }
        let curIdx = list.firstIndex(where: { $0.id == self.state.selectedID }) ?? 0
        let nextIdx = (curIdx + delta + list.count) % list.count
        let nextID = list[nextIdx].id
        self.state.selectedID = nextID
        if self.quickLookItemID != nil {
            self.quickLookItemID = nextID
        }
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
        } else if let stored = item.storedRecord {
            AnalyticsDashboardWindowController.shared.openDocument(stored)
        }
    }
    
    
    private func openAll(items: [DocumentCenterState.ManagedDocumentItem]) {
        guard !items.isEmpty else { return }
        if let onOpenAllDocuments = self.onOpenAllDocuments {
            onOpenAllDocuments(items)
        } else {
            for item in items { self.open(item: item) }
        }
    }
    
    
    private func delete(item: DocumentCenterState.ManagedDocumentItem, in list: [DocumentCenterState.ManagedDocumentItem]) {
        if item.isTrashed {
            self.permanentlyDelete(item: item)
            return
        }
        if let idx = list.firstIndex(where: { $0.id == item.id }) {
            let nextItem = list.indices.contains(idx + 1) ? list[idx + 1] : (idx > 0 ? list[idx - 1] : nil)
            self.state.selectedID = nextItem?.id
        }
        if self.quickLookItemID == item.id { self.quickLookItemID = nil }
        if let onDeleteDocument = self.onDeleteDocument {
            onDeleteDocument(item)
        } else if let recordID = item.dbRecordID {
            self.db.trashDocument(id: recordID, filePath: item.filePath)
            self.state.refresh()
        }
        self.showToast("已移入废纸篓")
    }
    
    
    private func restore(item: DocumentCenterState.ManagedDocumentItem) {
        self.db.restoreDocument(id: item.dbRecordID ?? item.id, filePath: item.filePath)
        self.state.refresh()
        self.showToast("已恢复")
    }
    
    
    private func permanentlyDelete(item: DocumentCenterState.ManagedDocumentItem) {
        self.confirmDestructive(title: "彻底删除「\(item.title)」？") {
            self.db.permanentlyDeleteDocument(id: item.dbRecordID ?? item.id, filePath: item.filePath)
            if self.quickLookItemID == item.id { self.quickLookItemID = nil }
            self.state.refresh()
            self.showToast("已彻底删除")
        }
    }
    
    
    private func confirmEmptyTrash() {
        self.confirmDestructive(title: "清空废纸篓（\(self.state.trashedItems.count) 篇）？") {
            self.db.emptyDocumentTrash()
            self.quickLookItemID = nil
            self.state.refresh()
            self.showToast("已清空废纸篓")
        }
    }
    
    
    private func confirmDestructive(title: String, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.alertStyle = .warning
        alert.addButton(withTitle: "彻底删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        action()
    }
    
    
    private func commitCreateGroup() {
        guard let created = self.db.createDocumentGroup(named: self.newGroupDraft) else {
            self.isCreatingGroup = false
            return
        }
        self.isCreatingGroup = false
        self.newGroupDraft = ""
        if let pending = self.pendingAssignAfterGroupCreate {
            self.pendingAssignAfterGroupCreate = nil
            self.move(item: pending, toGroup: created)
        } else {
            self.state.setClusterExpanded("group:\(created)", expanded: true)
            self.state.refresh()
            self.focusedClusterID = "group:\(created)"
            self.showToast("已新建分组「\(created)」")
        }
    }
    
    
    private func commitGroupRename(oldName: String) {
        let trimmed = self.groupRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        self.renamingGroupName = nil
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        if self.db.renameDocumentGroup(from: oldName, to: trimmed) {
            if self.state.sidebarFilter == .group(oldName) { self.state.sidebarFilter = .group(trimmed) }
            if self.focusedClusterID == "group:\(oldName)" { self.focusedClusterID = "group:\(trimmed)" }
            self.state.refresh()
            self.showToast("已重命名为「\(trimmed)」")
        } else {
            self.showToast("分组名称无效")
        }
    }
    
    
    private func move(item: DocumentCenterState.ManagedDocumentItem, toGroup groupName: String) {
        let recordID = item.dbRecordID ?? item.id
        self.db.assignDocumentGroup(
            id: recordID,
            filePath: item.filePath,
            groupName: groupName,
            fallbackTitle: item.title,
            fallbackSyntax: item.syntax,
            fallbackContent: item.content
        )
        self.state.refresh()
        self.showToast(groupName.isEmpty ? "已移至未分组" : "已移至「\(groupName)」")
    }
    
    
    private func commitRename(for item: DocumentCenterState.ManagedDocumentItem) {
        let trimmed = self.renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.isRenaming = false
            return
        }
        
        var targetSelectionID = item.id
        if let liveDoc = self.state.liveDocument(for: item.id) {
            do {
                let newName = try WorkspaceOrganizer.renameDocument(liveDoc, to: trimmed)
                targetSelectionID = DocumentCenterState.canonicalKey(
                    filePath: liveDoc.fileURL?.path(percentEncoded: false),
                    rawID: liveDoc.databaseDocumentID
                )
                self.showToast("已重命名为「\(newName)」")
            } catch {
                CotLogger.shared.error(category: .document, "Document Center live rename failed", error: error)
                self.showToast("重命名失败")
            }
        } else if let recordID = item.dbRecordID, item.filePath == nil {
            self.db.renameDocument(oldID: recordID, oldFilePath: nil, newID: recordID, newTitle: trimmed, newFilePath: nil)
            self.showToast("已重命名为「\(trimmed)」")
        } else if let filePath = item.filePath {
            let oldURL = URL(filePath: filePath)
            let desiredName = WorkspaceOrganizer.resolvedRenamedFilename(for: trimmed, preservingExtensionOf: oldURL)
            do {
                let newURL = try WorkspaceOrganizer.coordinatedMoveFile(from: oldURL, toDesiredFilename: desiredName)
                let newPath = newURL.path(percentEncoded: false)
                if let recordID = item.dbRecordID {
                    self.db.renameDocument(
                        oldID: recordID,
                        oldFilePath: filePath,
                        newID: newPath,
                        newTitle: newURL.lastPathComponent,
                        newFilePath: newPath
                    )
                }
                targetSelectionID = DocumentCenterState.canonicalKey(filePath: newPath, rawID: newPath)
                self.showToast("已重命名为「\(newURL.lastPathComponent)」")
            } catch {
                CotLogger.shared.error(category: .document, "Document Center file rename failed", error: error)
                self.showToast("重命名失败")
            }
        }
        self.isRenaming = false
        self.state.refresh()
        self.state.selectedID = targetSelectionID
    }
    
    
    private func showToast(_ message: String) {
        self.toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.14)) { self.toastMessage = message }
        self.toastTask = Task {
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.16)) { self.toastMessage = nil }
        }
    }
}
