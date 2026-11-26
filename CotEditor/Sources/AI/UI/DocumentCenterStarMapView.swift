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
    @State private var layoutStyle: StarMapLayoutStyle = .timeline
    @State private var quickLook = StarMapQuickLookController()
    @State private var panRequestToken = 0
    @State private var fitRequestToken = 0
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
    @State private var multiSelectedIDs: Set<String> = []
    @State private var isShowingOrganizeLog = false
    
    
    var body: some View {
        let displayedItems = self.state.displayedItems
        let activeItem = self.selectedItem(in: displayedItems)
        let tokens = DashPalette.editorialTokens(isDark: self.colorScheme == .dark)
        let clusters = self.state.buildStarMapClusters(tokens: tokens)
        let hasQuery = !self.state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let quickLookItem = self.quickLook.mountedID.flatMap { id in
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
                    showingQuickLook: self.quickLook.isOpen,
                    tokens: tokens
                )
            }
            .background(tokens.canvasTop)
            
            if let qItem = quickLookItem {
                self.quickLookOverlay(qItem: qItem, displayedItems: displayedItems, tokens: tokens)
                    .zIndex(20)
            }
            
            if let toastMessage = self.toastMessage {
                self.toastPill(message: toastMessage, tokens: tokens)
                    .zIndex(30)
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
            self.quickLook.cancelPendingDismiss()
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
                    multiSelectedLeafIDs: self.multiSelectedIDs,
                    focusedClusterID: self.focusedClusterID,
                    searchQuery: self.state.searchText,
                    panRequestToken: self.panRequestToken,
                    fitRequestToken: self.fitRequestToken,
                    isOverlayBlockingInteraction: self.quickLook.mountedID != nil,
                    layoutStyle: self.layoutStyle,
                    onSelectedLeafFrameChange: { rect in
                        self.quickLook.anchorRect = rect.map { $0.offsetBy(dx: 0, dy: 49) }
                    },
                    onSelectLeaf: { leafID in
                        self.isRenaming = false
                        if !self.multiSelectedIDs.isEmpty {
                            self.toggleMultiSelection(for: leafID)
                        } else {
                            self.state.selectedID = leafID
                        }
                    },
                    onCommandSelectLeaf: { leafID in
                        self.isRenaming = false
                        self.toggleMultiSelection(for: leafID)
                    },
                    onDoubleClickLeaf: { leafID in
                        self.multiSelectedIDs.removeAll()
                        self.state.selectedID = leafID
                        guard let target = displayedItems.first(where: { $0.id == leafID }) else { return }
                        if target.isTrashed {
                            self.quickLook.open(target.id)
                        } else {
                            self.open(item: target)
                        }
                    },
                    onToggleCluster: { clusterID in
                        if self.state.collapsedClusterIDs.contains(clusterID) {
                            self.state.collapsedClusterIDs.remove(clusterID)
                            self.focusedClusterID = clusterID
                        } else {
                            self.state.collapsedClusterIDs.insert(clusterID)
                            if self.focusedClusterID == clusterID {
                                self.focusedClusterID = nil
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
                        self.quickLook.open(hitID)
                    },
                    onOpenHit: { hitID in
                        if let target = displayedItems.first(where: { $0.id == hitID }) ?? self.state.items.first(where: { $0.id == hitID }) {
                            self.open(item: target)
                        }
                    }
                )
                .padding(16)
            }
            
            if !showingQuickLook {
                let batchItems = displayedItems.filter { self.multiSelectedIDs.contains($0.id) && !$0.isTrashed }
                if !batchItems.isEmpty {
                    VStack {
                        Spacer()
                        self.batchSelectionCapsule(items: batchItems, allItems: displayedItems, tokens: tokens)
                            .padding(.bottom, 16)
                    }
                    .frame(maxWidth: .infinity)
                } else if let activeItem {
                    VStack {
                        Spacer()
                        self.bottomSelectionCapsule(item: activeItem, allItems: displayedItems, tokens: tokens)
                            .padding(.bottom, 16)
                    }
                    .frame(maxWidth: .infinity)
                }
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
        
        let indexText: String? = navList.count > 1 ? "\(curIdx + 1) / \(navList.count)" : nil
        
        return StarMapQuickLookOverlay(
            isPresented: self.quickLook.isVisible,
            title: qItem.title,
            subtitle: "\(qItem.groupName.isEmpty ? "未分组" : qItem.groupName) · \(qItem.compactCharCount) · \(qItem.relativeTimeText)",
            indexText: indexText,
            anchorRect: self.quickLook.anchorRect,
            isExpanded: self.quickLook.isExpanded,
            canStepPrevious: canPrev,
            canStepNext: canNext,
            onToggleExpand: {
                self.quickLook.isExpanded.toggle()
            },
            onPrevious: {
                guard canPrev else { return }
                let prev = navList[curIdx - 1]
                self.state.selectedID = prev.id
                self.quickLook.step(to: prev.id)
                self.panRequestToken &+= 1
            },
            onNext: {
                guard canNext else { return }
                let next = navList[curIdx + 1]
                self.state.selectedID = next.id
                self.quickLook.step(to: next.id)
                self.panRequestToken &+= 1
            },
            onClose: {
                self.quickLook.close(animated: true)
            },
            headerActions: {
                HStack(spacing: 6) {
                    if qItem.isTrashed {
                        Button("恢复") {
                            self.restore(item: qItem)
                            self.quickLook.close(animated: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Button("打开") {
                            self.quickLook.close(animated: false)
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
                                        self.quickLook.step(to: entry.item.id)
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
                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            
            Text("文档星图")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tokens.primaryInk)
            
            self.scopeFilterBar(tokens: tokens)
            self.layoutStyleSwitcher(tokens: tokens)
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
        .background(tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    
    private func layoutStyleSwitcher(tokens: StudioColorTokens) -> some View {
        HStack(spacing: 2) {
            self.scopeChip(title: "时间线", isActive: self.layoutStyle == .timeline, tokens: tokens) {
                self.layoutStyle = .timeline
            }
            self.scopeChip(title: "星图", isActive: self.layoutStyle == .orbital, tokens: tokens) {
                self.layoutStyle = .orbital
            }
        }
        .padding(2.5)
        .background(tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(tokens.primaryInk.opacity(0.5))
                }
                .foregroundStyle(tokens.primaryInk.opacity(0.84))
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(self.state.timeHorizon == .all ? tokens.primaryInk.opacity(0.84) : tokens.accentText)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tokens.primaryInk.opacity(0.45))
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                self.state.timeHorizon == .all ? tokens.inset : tokens.accent.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(tokens.primaryInk.opacity(0.80))
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
    }
    
    
    private func searchField(tokens: StudioColorTokens) -> some View {
        StarMapSearchField(
            placeholder: "搜索文档",
            text: self.$searchDraft,
            hitCount: self.state.searchHits.count,
            showCount: !self.searchDraft.isEmpty,
            isFocused: self.$isSearchFocused,
            tokens: tokens,
            onSubmit: {
                self.searchDebounceTask?.cancel()
                let query = self.searchDraft
                self.unfocusSearchField()
                self.searchDebounceTask = Task {
                    guard await self.state.applySearch(query), let firstHit = self.state.searchHits.first else { return }
                    self.state.selectedID = firstHit.id
                    self.panRequestToken &+= 1
                }
            },
            onClear: {
                self.searchDebounceTask?.cancel()
                self.searchDraft = ""
                self.state.searchText = ""
            }
        )
    }
    
    
    @ViewBuilder
    private func organizeAndCreateControls(tokens: StudioColorTokens) -> some View {
        if self.state.sidebarFilter == .trash && !self.state.displayedItems.isEmpty {
            Button("清空废纸篓") {
                self.confirmEmptyTrash()
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.red)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
        
        if self.state.isAgentOrganizing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(self.state.agentOrganizeProgressText)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(tokens.accentText)
                Button("取消") {
                    self.cancelAgentOrganize()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.primaryInk.opacity(0.65))
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(tokens.positivePillBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            if let summary = self.state.agentOrganizeSummary {
                let hasLogs = !self.state.lastOrganizeLogEntries.isEmpty || !self.state.lastOrganizeMergeLogs.isEmpty
                HStack(spacing: 6) {
                    Button {
                        if hasLogs {
                            self.isShowingOrganizeLog.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(summary)
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundStyle(tokens.accentText)
                            if hasLogs {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(tokens.accentText.opacity(0.75))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .popover(isPresented: self.$isShowingOrganizeLog, arrowEdge: .bottom) {
                        self.organizeMergeLogPopover(tokens: tokens)
                    }
                    if !self.state.lastOrganizeUndoSnapshot.isEmpty {
                        Button("撤销") {
                            self.isShowingOrganizeLog = false
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
                        self.isShowingOrganizeLog = false
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
                .background(tokens.positivePillBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            
            Button {
                self.runAgentAutoOrganize()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("一键整理")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(tokens.accentText)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(tokens.positivePillBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tokens.accent.opacity(0.28), lineWidth: 0.75))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(tokens.onAccentInk)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(tokens.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .frame(maxWidth: 680)
        .background(tokens.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tokens.hairlineStrong, lineWidth: 0.8))
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
            self.state.selectedID = item.id
            self.quickLook.open(item.id)
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
            if self.state.items.count >= 2 {
                let candidates = self.rankedMergeTargets(for: item, limit: 8)
                Menu {
                    if !candidates.isEmpty {
                        ForEach(candidates, id: \.item.id) { entry in
                            Button("\(entry.item.title)  ·  \(entry.badge)") {
                                self.mergeDocumentsManually([item, entry.item])
                            }
                        }
                        Divider()
                    }
                    Button("多选合并…") {
                        self.multiSelectedIDs = [item.id]
                        self.showToast("已选 \(self.multiSelectedIDs.count) 篇")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("合并")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(tokens.primaryInk.opacity(0.84))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(tokens.inset, in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .pointerStyle(.link)
            }
            
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
            let groupItems = self.state.items.filter { $0.groupName == groupName }
            Button("打开全部分组文档") {
                self.openAll(items: groupItems)
            }
            if groupItems.count >= 2 {
                Button("合并组内文档（\(groupItems.count) 篇）") {
                    self.mergeDocumentsManually(groupItems, preferredGroup: groupName)
                }
            }
            let otherGroups = self.db.documentGroups.filter { $0 != groupName }
            if !otherGroups.isEmpty && !groupItems.isEmpty {
                Menu("并入其他分组") {
                    ForEach(otherGroups, id: \.self) { targetGroup in
                        Button(targetGroup) {
                            self.mergeGroup(from: groupName, into: targetGroup)
                        }
                    }
                }
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
            self.quickLook.open(item.id)
        }
        if item.isTrashed {
            Button("恢复") { self.restore(item: item) }
            Divider()
            Button("彻底删除", role: .destructive) { self.permanentlyDelete(item: item) }
        } else {
            Button("在编辑器打开") { self.open(item: item) }
            if self.state.items.count >= 2 {
                let candidates = self.rankedMergeTargets(for: item, limit: 8)
                Menu("合并到…") {
                    ForEach(candidates, id: \.item.id) { entry in
                        Button("\(entry.item.title)  ·  \(entry.badge)") {
                            self.mergeDocumentsManually([item, entry.item])
                        }
                    }
                }
                let isMulti = self.multiSelectedIDs.contains(item.id)
                Button(isMulti ? "移出多选" : "加入多选合并") {
                    self.toggleMultiSelection(for: item.id)
                }
            }
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
            
            // Reset view into a crisp, uncluttered post-organize constellation.
            self.focusedClusterID = nil
            self.quickLook.close(animated: false)
            self.isRenaming = false
            if self.state.sidebarFilter != .all && self.state.sidebarFilter != .trash {
                self.state.sidebarFilter = .all
            }
            self.state.refresh()
            self.state.selectedID = nil
            self.state.applyCleanPostOrganizeClusterState()
            self.fitRequestToken &+= 1
            
            var summaryParts: [String] = []
            if stats.deletedJunk > 0 { summaryParts.append("删 \(stats.deletedJunk) 无效") }
            if stats.mergedDuplicates > 0 { summaryParts.append("合并 \(stats.mergedDuplicates) 篇同类") }
            if stats.renamed > 0 { summaryParts.append("重命名 \(stats.renamed) 篇") }
            if stats.groupCount > 0 {
                summaryParts.append("\(stats.groupCount) 组")
            } else if stats.regrouped > 0 {
                summaryParts.append("归类 \(stats.regrouped) 篇")
            }
            
            if summaryParts.isEmpty {
                self.showToast("星图已整理清晰")
            } else {
                self.state.agentOrganizeSummary = summaryParts.joined(separator: " · ")
            }
        }
    }
    
    
    private struct OrganizeApplyStats {
        var deletedJunk: Int = 0
        var mergedDuplicates: Int = 0
        var renamed: Int = 0
        var regrouped: Int = 0
        var groupCount: Int = 0
        
        var hasChanges: Bool {
            self.deletedJunk > 0 || self.mergedDuplicates > 0 || self.renamed > 0 || self.regrouped > 0
        }
    }
    
    
    private func applyOrganizeFullPlan(
        _ fullPlan: OrganizeFullPlan,
        itemsByID: [String: DocumentCenterState.ManagedDocumentItem]
    ) -> OrganizeApplyStats {
        var undoEntries: [DocumentCenterState.OrganizeUndoEntry] = []
        var existingGroupSet = Set(self.db.documentGroups)
        var createdGroups: [String] = []
        var touchedGroups = Set<String>()
        var renamedLogs: [DocumentCenterState.OrganizeLogEntry] = []
        var stats = OrganizeApplyStats()
        
        let mergedByPrimaryID = Dictionary(uniqueKeysWithValues: fullPlan.funnel.mergeClusters.map { ($0.primary.id, $0) })
        
        self.db.withTransaction {
            stats.deletedJunk = self.applyJunkDeletions(
                fullPlan.funnel.junkToDelete,
                itemsByID: itemsByID,
                undoEntries: &undoEntries
            )
            let mergeOutcome = self.applyDuplicateMerges(
                fullPlan.funnel.mergeClusters,
                itemsByID: itemsByID,
                undoEntries: &undoEntries
            )
            stats.mergedDuplicates = mergeOutcome.merged
            stats.renamed += mergeOutcome.renamed
            self.applyShardedAssignments(
                fullPlan.assignments,
                usedAI: fullPlan.usedAI,
                itemsByID: itemsByID,
                mergedByPrimaryID: mergedByPrimaryID,
                existingGroupSet: &existingGroupSet,
                createdGroups: &createdGroups,
                touchedGroups: &touchedGroups,
                undoEntries: &undoEntries,
                renamedLogs: &renamedLogs,
                stats: &stats
            )
        }
        
        var removedEmptyGroups: [String] = []
        if stats.hasChanges {
            removedEmptyGroups = self.db.pruneEmptyDocumentGroups(reloadAfter: false)
            self.db.reloadDocuments()
        }
        let activeDocs = self.db.documents.filter { !$0.id.hasPrefix("weekly:") }
        var groupCounts: [String: Int] = [:]
        for doc in activeDocs where !doc.groupName.isEmpty {
            groupCounts[doc.groupName, default: 0] += 1
        }
        stats.groupCount = groupCounts.count
        self.state.lastOrganizeUndoSnapshot = undoEntries
        self.state.lastOrganizeCreatedGroups = createdGroups
        self.state.lastOrganizeRemovedGroups = removedEmptyGroups
        self.state.lastOrganizeMergeLogs = fullPlan.funnel.mergeClusters.map { cluster in
            let sources = ([cluster.primary.title] + cluster.duplicates.map(\.title)).joined(separator: " + ")
            return "\(cluster.bestTitle) ← \(sources)"
        }
        
        var logEntries: [DocumentCenterState.OrganizeLogEntry] = []
        for decision in fullPlan.funnel.junkToDelete {
            logEntries.append(.init(kind: .deleted, title: decision.item.title, detail: decision.displayReason))
        }
        for cluster in fullPlan.funnel.mergeClusters {
            let sources = ([cluster.primary.title] + cluster.duplicates.map(\.title)).joined(separator: " + ")
            logEntries.append(.init(kind: .merged, title: "\(cluster.bestTitle) ← \(sources)", detail: cluster.reason))
        }
        logEntries.append(contentsOf: renamedLogs)
        for (name, count) in groupCounts.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }) {
            logEntries.append(.init(kind: .groupSummary, title: name, detail: "\(count) 篇"))
        }
        self.state.lastOrganizeLogEntries = logEntries
        return stats
    }
    
    
    private func applyJunkDeletions(
        _ decisions: [OrganizeJunkDecision],
        itemsByID: [String: DocumentCenterState.ManagedDocumentItem],
        undoEntries: inout [DocumentCenterState.OrganizeUndoEntry]
    ) -> Int {
        var count = 0
        for decision in decisions {
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
            count += 1
        }
        return count
    }
    
    
    private func applyDuplicateMerges(
        _ clusters: [OrganizeMergeCluster],
        itemsByID: [String: DocumentCenterState.ManagedDocumentItem],
        undoEntries: inout [DocumentCenterState.OrganizeUndoEntry]
    ) -> (merged: Int, renamed: Int) {
        var mergedCount = 0
        var renamedCount = 0
        for cluster in clusters {
            guard let primaryItem = itemsByID[cluster.primary.id] else { continue }
            let primaryRecordID = primaryItem.dbRecordID ?? primaryItem.id
            let didRenamePrimary = (cluster.bestTitle != primaryItem.title)
            undoEntries.append(DocumentCenterState.OrganizeUndoEntry(
                kind: .mergedPrimary,
                itemID: primaryItem.id,
                dbRecordID: primaryRecordID,
                filePath: primaryItem.filePath,
                previousGroup: primaryItem.groupName,
                previousTitle: primaryItem.title,
                titleWasChanged: didRenamePrimary,
                syntax: primaryItem.syntax,
                content: primaryItem.content
            ))
            
            if let liveDoc = self.state.liveDocument(for: primaryItem.id) {
                if cluster.mergedContent != liveDoc.textStorage.string {
                    liveDoc.textStorage.replaceCharacters(
                        in: NSRange(location: 0, length: liveDoc.textStorage.length),
                        with: cluster.mergedContent
                    )
                    if liveDoc.fileURL == nil {
                        liveDoc.updateChangeCount(.changeCleared)
                    }
                }
                if didRenamePrimary, liveDoc.fileURL == nil {
                    liveDoc.displayName = cluster.bestTitle
                    liveDoc.isExplicitlyNamed = true
                }
            }
            if didRenamePrimary {
                renamedCount += 1
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
                mergedCount += 1
            }
        }
        return (mergedCount, renamedCount)
    }
    
    
    private func applyShardedAssignments(
        _ assignments: [DocumentCenterAgentOrganizer.Assignment],
        usedAI: Bool,
        itemsByID: [String: DocumentCenterState.ManagedDocumentItem],
        mergedByPrimaryID: [String: OrganizeMergeCluster],
        existingGroupSet: inout Set<String>,
        createdGroups: inout [String],
        touchedGroups: inout Set<String>,
        undoEntries: inout [DocumentCenterState.OrganizeUndoEntry],
        renamedLogs: inout [DocumentCenterState.OrganizeLogEntry],
        stats: inout OrganizeApplyStats
    ) {
        for assignment in assignments {
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
                      item.filePath == nil,
                      (usedAI || DocumentCenterAgentOrganizer.isWeakScratchTitle(effectiveTitle, hasFilePath: false))
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
            
            // Rename FIRST so live document sync never overwrites the newly assigned group.
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
                renamedLogs.append(.init(
                    kind: .renamed,
                    title: "\(effectiveTitle) → \(newTitle)",
                    detail: targetGroup.isEmpty ? nil : targetGroup
                ))
                stats.renamed += 1
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
                stats.regrouped += 1
            }
        }
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
        let removedGroups = self.state.lastOrganizeRemovedGroups
        guard !entries.isEmpty else { return }
        
        self.db.withTransaction {
            for group in removedGroups {
                self.db.createDocumentGroup(named: group)
            }
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
                        self.db.assignDocumentGroup(
                            id: entry.dbRecordID,
                            filePath: entry.filePath,
                            groupName: entry.previousGroup,
                            fallbackTitle: entry.previousTitle,
                            fallbackSyntax: entry.syntax,
                            fallbackContent: entry.content,
                            reloadAfter: false
                        )
                }
            }
            
            for group in createdGroups where !self.db.documents.contains(where: { $0.groupName == group }) {
                self.db.deleteDocumentGroup(named: group)
            }
        }
        self.db.reloadDocuments()
        
        self.state.lastOrganizeUndoSnapshot = []
        self.state.lastOrganizeCreatedGroups = []
        self.state.lastOrganizeRemovedGroups = []
        self.state.lastOrganizeMergeLogs = []
        self.state.lastOrganizeLogEntries = []
        self.state.agentOrganizeSummary = nil
        self.state.sidebarFilter = .all
        self.state.refresh()
        self.fitRequestToken &+= 1
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
        if !self.multiSelectedIDs.isEmpty {
            self.multiSelectedIDs.removeAll()
            return true
        }
        if self.isShowingOrganizeLog {
            self.isShowingOrganizeLog = false
            return true
        }
        if self.isRenaming {
            self.isRenaming = false
            return true
        }
        if self.quickLook.isOpen {
            self.quickLook.close(animated: true)
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
                self.quickLook.close(animated: true)
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
                    if self.quickLook.isOpen {
                        self.quickLook.close(animated: true)
                        return nil
                    }
                    if let active = self.selectedItem(in: navList) {
                        self.state.selectedID = active.id
                        self.quickLook.open(active.id)
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
                        self.quickLook.close(animated: false)
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
        if self.quickLook.isOpen {
            self.quickLook.step(to: nextID)
            self.panRequestToken &+= 1
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
        if self.quickLook.mountedID == item.id { self.quickLook.close(animated: false) }
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
            if self.quickLook.mountedID == item.id { self.quickLook.close(animated: false) }
            self.state.refresh()
            self.showToast("已彻底删除")
        }
    }
    
    
    private func confirmEmptyTrash() {
        self.confirmDestructive(title: "清空废纸篓（\(self.state.trashedItems.count) 篇）？") {
            self.db.emptyDocumentTrash()
            self.quickLook.close(animated: false)
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
    
    
    // MARK: Batch Multi-Select Capsule, Manual Merge & Organize Detail Popover
    
    private func batchSelectionCapsule(
        items: [DocumentCenterState.ManagedDocumentItem],
        allItems: [DocumentCenterState.ManagedDocumentItem],
        tokens: StudioColorTokens
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tokens.accent)
            
            Text("已选 \(items.count) 篇")
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(tokens.primaryInk)
            
            Spacer(minLength: 8)
            
            if items.count >= 2 {
                Button {
                    self.mergeDocumentsManually(items)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("合并为 1 篇")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(tokens.onAccentInk)
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .background(tokens.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            
            Menu {
                Button("未分组") { self.moveBatch(items: items, toGroup: "") }
                if !self.db.documentGroups.isEmpty {
                    Divider()
                    ForEach(self.db.documentGroups, id: \.self) { group in
                        Button(group) { self.moveBatch(items: items, toGroup: group) }
                    }
                }
            } label: {
                Text("移至分组")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(tokens.primaryInk.opacity(0.84))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(tokens.inset, in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .pointerStyle(.link)
            
            Button {
                for item in items {
                    self.delete(item: item, in: allItems)
                }
                self.multiSelectedIDs.removeAll()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 26, height: 26)
                    .background(Color.red.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            Button("取消") {
                self.multiSelectedIDs.removeAll()
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(tokens.primaryInk.opacity(0.70))
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(tokens.inset, in: Capsule())
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: 540)
        .background(tokens.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tokens.hairlineStrong, lineWidth: 0.9))
        .shadow(color: tokens.cardShadow, radius: 10, y: 4)
        .padding(.horizontal, 24)
    }
    
    
    private func organizeMergeLogPopover(tokens: StudioColorTokens) -> some View {
        let entries = self.state.lastOrganizeLogEntries
        let deletedEntries = entries.filter { $0.kind == .deleted }
        let mergedEntries = entries.filter { $0.kind == .merged }
        let renamedEntries = entries.filter { $0.kind == .renamed }
        let groupEntries = entries.filter { $0.kind == .groupSummary }
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("整理明细")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.primaryInk)
                Spacer()
                if !self.state.lastOrganizeUndoSnapshot.isEmpty {
                    Button("撤销全部") {
                        self.isShowingOrganizeLog = false
                        self.undoAgentOrganize()
                    }
                    .controlSize(.small)
                }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !deletedEntries.isEmpty {
                        self.organizeLogSection(
                            heading: "已清理",
                            count: deletedEntries.count,
                            symbol: "trash",
                            tint: .red,
                            entries: deletedEntries,
                            tokens: tokens
                        )
                    }
                    if !mergedEntries.isEmpty {
                        self.organizeLogSection(
                            heading: "已合并",
                            count: mergedEntries.count,
                            symbol: "arrow.triangle.merge",
                            tint: tokens.accent,
                            entries: mergedEntries,
                            tokens: tokens
                        )
                    }
                    if !renamedEntries.isEmpty {
                        self.organizeLogSection(
                            heading: "已重命名",
                            count: renamedEntries.count,
                            symbol: "pencil",
                            tint: tokens.primaryInk.opacity(0.65),
                            entries: renamedEntries,
                            tokens: tokens
                        )
                    }
                    if !groupEntries.isEmpty {
                        self.organizeLogSection(
                            heading: "工作主线分组",
                            count: groupEntries.count,
                            symbol: "folder",
                            tint: tokens.accent,
                            entries: groupEntries,
                            tokens: tokens
                        )
                    }
                    if entries.isEmpty {
                        ForEach(Array(self.state.lastOrganizeMergeLogs.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "arrow.triangle.merge")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(tokens.accent)
                                    .padding(.top, 2)
                                Text(line)
                                    .font(.system(size: 12))
                                    .foregroundStyle(tokens.primaryInk.opacity(0.88))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .padding(14)
        .frame(width: 380)
    }
    
    
    private func organizeLogSection(
        heading: String,
        count: Int,
        symbol: String,
        tint: Color,
        entries: [DocumentCenterState.OrganizeLogEntry],
        tokens: StudioColorTokens
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(heading)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(tokens.primaryInk.opacity(0.62))
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
            }
            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: 13, alignment: .center)
                        .padding(.top, 2)
                    Text(entry.title)
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.primaryInk.opacity(0.90))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    if let detail = entry.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(tokens.primaryInk.opacity(0.54))
                            .lineLimit(1)
                    }
                }
            }
        }
    }
    
    
    private func toggleMultiSelection(for leafID: String) {
        if self.multiSelectedIDs.isEmpty, let existing = self.state.selectedID, existing != leafID {
            self.multiSelectedIDs.insert(existing)
        }
        if self.multiSelectedIDs.contains(leafID) {
            self.multiSelectedIDs.remove(leafID)
        } else {
            self.multiSelectedIDs.insert(leafID)
            self.state.selectedID = leafID
        }
    }
    
    
    private func rankedMergeTargets(
        for source: DocumentCenterState.ManagedDocumentItem,
        limit: Int
    ) -> [(item: DocumentCenterState.ManagedDocumentItem, badge: String)] {
        let toFunnel: (DocumentCenterState.ManagedDocumentItem) -> OrganizeFunnelInput = { item in
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
        let itemByID = Dictionary(uniqueKeysWithValues: self.state.items.map { ($0.id, $0) })
        let candidates = self.state.items.filter { !$0.isTrashed && $0.id != source.id }.map(toFunnel)
        let ranked = OrganizeTopicSignature.rankedMergeCandidates(for: toFunnel(source), in: candidates, limit: limit)
        return ranked.compactMap { entry in
            guard let item = itemByID[entry.item.id] else { return nil }
            return (item, entry.badge)
        }
    }
    
    
    private func mergeDocumentsManually(
        _ rawItems: [DocumentCenterState.ManagedDocumentItem],
        preferredGroup: String? = nil
    ) {
        var seen = Set<String>()
        let unique = rawItems.filter { !$0.isTrashed && seen.insert($0.id).inserted }
        guard unique.count >= 2 else { return }
        
        let funnelInputs = unique.map { item in
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
        let ranked = funnelInputs.sorted { lhs, rhs in
            if (lhs.filePath != nil) != (rhs.filePath != nil) { return lhs.filePath != nil }
            if lhs.isUntitled != rhs.isUntitled { return !lhs.isUntitled }
            if lhs.content.count != rhs.content.count { return lhs.content.count > rhs.content.count }
            return lhs.updatedAt > rhs.updatedAt
        }
        let primary = ranked[0]
        let duplicates = Array(ranked.dropFirst())
        let mergedContent = DocumentOrganizeFunnel.mergeStructuredContents(primary: primary, secondaries: duplicates)
        let bestTitle = OrganizeTopicSignature.cleanSeriesTitle(primary: primary, secondaries: duplicates)
        let titleSig = OrganizeTopicSignature.extract(title: bestTitle, content: mergedContent, isUntitled: false)
        let resolvedGroup: String = {
            if let preferredGroup, !preferredGroup.isEmpty { return preferredGroup }
            let groups = ranked.map(\.currentGroup).filter { !$0.isEmpty }
            return groups.max { lhs, rhs in
                OrganizeTopicSignature.titleAffinityScore(for: titleSig, groupName: lhs)
                    < OrganizeTopicSignature.titleAffinityScore(for: titleSig, groupName: rhs)
            } ?? primary.currentGroup
        }()
        
        let cluster = OrganizeMergeCluster(
            primary: primary,
            duplicates: duplicates,
            mergedContent: mergedContent,
            bestGroup: resolvedGroup,
            bestTitle: bestTitle,
            reason: "手动合并"
        )
        let itemsByID = Dictionary(uniqueKeysWithValues: unique.map { ($0.id, $0) })
        var undoEntries: [DocumentCenterState.OrganizeUndoEntry] = []
        var removedEmptyGroups: [String] = []
        
        self.db.withTransaction {
            _ = self.applyDuplicateMerges([cluster], itemsByID: itemsByID, undoEntries: &undoEntries)
            removedEmptyGroups = self.db.pruneEmptyDocumentGroups(reloadAfter: false)
        }
        self.db.reloadDocuments()
        
        self.multiSelectedIDs.removeAll()
        self.state.lastOrganizeUndoSnapshot = undoEntries
        self.state.lastOrganizeCreatedGroups = []
        self.state.lastOrganizeRemovedGroups = removedEmptyGroups
        let manualMergeLine = "\(bestTitle) ← \(unique.map(\.title).joined(separator: " + "))"
        self.state.lastOrganizeMergeLogs = [manualMergeLine]
        self.state.lastOrganizeLogEntries = [.init(kind: .merged, title: manualMergeLine, detail: "手动合并")]
        self.state.agentOrganizeSummary = "已合并 \(unique.count) 篇为「\(bestTitle)」"
        self.state.refresh()
        self.state.selectedID = primary.id
        self.fitRequestToken &+= 1
    }
    
    
    private func moveBatch(items: [DocumentCenterState.ManagedDocumentItem], toGroup groupName: String) {
        self.db.withTransaction {
            for item in items {
                self.db.assignDocumentGroup(
                    id: item.dbRecordID ?? item.id,
                    filePath: item.filePath,
                    groupName: groupName,
                    fallbackTitle: item.title,
                    fallbackSyntax: item.syntax,
                    fallbackContent: item.content,
                    reloadAfter: false
                )
            }
            _ = self.db.pruneEmptyDocumentGroups(reloadAfter: false)
        }
        self.db.reloadDocuments()
        self.multiSelectedIDs.removeAll()
        self.state.refresh()
        self.showToast(groupName.isEmpty ? "已移动 \(items.count) 篇至未分组" : "已移动 \(items.count) 篇至「\(groupName)」")
    }
    
    
    private func mergeGroup(from donorGroup: String, into targetGroup: String) {
        guard donorGroup != targetGroup else { return }
        let donorItems = self.state.items.filter { $0.groupName == donorGroup }
        guard !donorItems.isEmpty else { return }
        var undoEntries: [DocumentCenterState.OrganizeUndoEntry] = []
        
        self.db.withTransaction {
            for item in donorItems {
                let recordID = item.dbRecordID ?? item.id
                undoEntries.append(DocumentCenterState.OrganizeUndoEntry(
                    kind: .modified,
                    itemID: item.id,
                    dbRecordID: recordID,
                    filePath: item.filePath,
                    previousGroup: item.groupName,
                    previousTitle: item.title,
                    titleWasChanged: false,
                    syntax: item.syntax,
                    content: item.content
                ))
                self.db.assignDocumentGroup(
                    id: recordID,
                    filePath: item.filePath,
                    groupName: targetGroup,
                    fallbackTitle: item.title,
                    fallbackSyntax: item.syntax,
                    fallbackContent: item.content,
                    reloadAfter: false
                )
            }
            self.db.deleteDocumentGroup(named: donorGroup)
        }
        self.db.reloadDocuments()
        
        if self.focusedClusterID == "group:\(donorGroup)" {
            self.focusedClusterID = "group:\(targetGroup)"
        }
        if self.state.sidebarFilter == .group(donorGroup) {
            self.state.sidebarFilter = .group(targetGroup)
        }
        self.state.lastOrganizeUndoSnapshot = undoEntries
        self.state.lastOrganizeCreatedGroups = []
        self.state.lastOrganizeRemovedGroups = [donorGroup]
        let groupMergeLine = "分组「\(donorGroup)」→「\(targetGroup)」（\(donorItems.count) 篇）"
        self.state.lastOrganizeMergeLogs = [groupMergeLine]
        self.state.lastOrganizeLogEntries = [.init(kind: .merged, title: groupMergeLine, detail: "合并分组")]
        self.state.agentOrganizeSummary = "已将「\(donorGroup)」并入「\(targetGroup)」"
        self.state.refresh()
        self.fitRequestToken &+= 1
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
