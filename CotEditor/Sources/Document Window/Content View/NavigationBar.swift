//
//  NavigationBar.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2024-02-04.
//
//  ---------------------------------------------------------------------------
//
//  © 2024-2026 1024jp
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

import SwiftUI
import StringUtils
import SyntaxParsers

/// The tab bar of a pane, listing the documents the pane shows.
struct NavigationBar: View {
    
    @State var outlineNavigator: OutlineNavigator
    var splitState: SplitState
    @State var tabs: PaneTabState
    
    
    var body: some View {
        
        HStack(alignment: .center, spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(self.tabs.tabs, id: \.id) { tab in
                        TabItem(tab: tab,
                                tabs: self.tabs,
                                isSelected: tab === self.tabs.selectedTab,
                                onSelect: { self.tabs.onSelect(tab) },
                                onClose: { self.tabs.onClose(tab) },
                                onTogglePin: { self.tabs.onTogglePin(tab) })
                    }
                    
                    NewTabButton(action: self.tabs.onNewTab)
                }
                .cotAnimation(.cotFast, value: self.tabs.tabs.map(\.id))
            }

            
            if self.outlineNavigator.items?.isEmpty == false {
                Divider()
                    .padding(.vertical, 4)
                    .padding(.horizontal, 3)
                
                OutlineNavigationView(navigator: $outlineNavigator)
            }
            
            Spacer()
            
            if self.tabs.canClosePane {
                self.closePaneButton
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, isLiquidGlass ? 4 : 2)
        .background(.windowBackground)
        .frame(height: isLiquidGlass ? 24 : 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Navigation Bar", table: "Document", comment: "accessibility label"))
    }
    
    
    // MARK: Private Views
    
    private var closePaneButton: some View {
        
        Button(action: self.tabs.onClosePane) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 16)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Close split editor", table: "Document", comment: "tooltip for button"))
    }
}


/// One tab in the tab bar.
private struct TabItem: View {
    
    var tab: PaneTab
    var tabs: PaneTabState
    var isSelected: Bool
    var onSelect: () -> Void
    var onClose: () -> Void
    var onTogglePin: () -> Void
    
    @State private var isHovering = false
    @State private var isDropTargeted = false
    
    
    var body: some View {
        
        self.titleButton
            .draggable(self.tab.id.uuidString) {
                // A compact, self-contained preview: the default snapshot of the tab
                // overlapped the tab under the cursor and made the titles double up.
                self.dragPreview
            }
            .dropDestination(for: String.self) { identifiers, _ in
                guard
                    let identifier = identifiers.first,
                    let draggedTab = self.tabs.tabs.first(where: { $0.id.uuidString == identifier }),
                    draggedTab !== self.tab
                else { return false }
                
                self.tabs.onMove(draggedTab, self.tab)
                
                return true
            } isTargeted: { isTargeted in
                self.isDropTargeted = isTargeted
            }
            .overlay {
                if self.isDropTargeted {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.15))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.accentColor, lineWidth: 1)
                        }
                }
            }
            .contextMenu {
                Button(self.tab.isPinned ? "取消固定" : "固定标签页") {
                    self.onTogglePin()
                }
                Divider()
                Button("关闭标签页") {
                    self.onClose()
                }
                .disabled(self.tab.isPinned || !self.tab.isClosable)
            }
    }
    
    
    // MARK: Private Views
    
    /// The image that follows the cursor while the tab is being dragged.
    private var dragPreview: some View {
        
        HStack(spacing: 3) {
            if self.tab.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            
            Text(self.tab.title)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }
    
    
    private var titleButton: some View {
        
        // The close button is a sibling of the title button, not nested inside it: a
        // Button inside a Button would swallow the close click in some macOS versions.
        HStack(spacing: 3) {
            // A pinned tab keeps its title; it only gains an accent pin and moves to the
            // front of the bar. The pin itself is a button so that unpinning never depends
            // on finding the context menu.
            if self.tab.isPinned {
                Button(action: self.onTogglePin) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("已固定，点击取消固定")
            }
            
            Button(action: self.onSelect) {
                Text(self.tab.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 160, alignment: .leading)
                    .foregroundStyle(self.isSelected ? Color.primary : Color.secondary)
                    .padding(.leading, self.tab.isPinned ? 0 : 4)
                    .padding(.vertical, 1)
            }
            .buttonStyle(.plain)
            .help(self.tab.title)
            
            if self.tab.isClosable, !self.tab.isPinned {
                Button(action: self.onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help("关闭标签页")
            }
        }
        .padding(.leading, self.tab.isPinned ? 4 : 0)
        .padding(.trailing, 4)
        .background {
            if self.isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.10))
            } else if self.isHovering {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.05))
            }
        }
        .onHover { self.isHovering = $0 }
        .cotAnimation(.cotFast, value: self.isSelected)
    }
}


/// The button to open a new tab at the end of the tab list.
private struct NewTabButton: View {
    
    var action: () -> Void
    
    @State private var isHovering = false
    
    
    var body: some View {
        
        Button(action: self.action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(self.isHovering ? Color.primary : Color.secondary)
                .frame(width: 18, height: 16)
        }
        .buttonStyle(.plain)
        .onHover { self.isHovering = $0 }
        .help("新建标签页")
    }
}


private struct OutlineNavigationView: View {
    
    @Binding var navigator: OutlineNavigator
    
    @State private var isLongExtraction = false
    @State private var extractionDelayTask: Task<Void, any Error>?
    
    
    var body: some View {
        
        HStack {
            if let items = self.navigator.items {
                if !items.isEmpty {
                    HStack(spacing: 0) {
                        if self.navigator.isVerticalOrientation {
                            self.nextButton(systemImage: "chevron.left")
                            self.previousButton(systemImage: "chevron.right")
                        } else {
                            self.previousButton(systemImage: "chevron.up")
                            self.nextButton(systemImage: "chevron.down")
                        }
                    }
                    
                    // Use AppKit-based picker to open programmatically (2024-05, macOS 14).
                    OutlinePicker(items: items, selection: $navigator.selection, isPresented: $navigator.isOutlinePickerPresented) {
                        self.navigator.textView?.select(range: $0.range)
                    }
                    .accessibilityLabel(String(localized: "Outline Menu", table: "Document", comment: "accessibility label"))
                }
            } else if self.isLongExtraction {
                Text("Extracting Outline…", tableName: "Document")
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            self.extractionDelayTask?.cancel()
        }
        .onChange(of: self.navigator.items, initial: true) { _, newValue in
            // show message only when parse takes more than 1 second.
            self.extractionDelayTask?.cancel()
            if newValue == nil {
                self.extractionDelayTask = Task {
                    try await Task.sleep(for: .seconds(1))
                    self.isLongExtraction = true
                }
            } else {
                self.extractionDelayTask = nil
                self.isLongExtraction = false
            }
        }
    }
    
    
    // MARK: Private Methods
    
    @ViewBuilder private func previousButton(systemImage: String) -> some View {
        
        Button {
            self.navigator.selectPreviousItem()
        } label: {
            Label(String(localized: "Previous Outline Item", table: "Document", comment: "accessibility label for button"), systemImage: systemImage)
                .frame(width: 18)
                .frame(maxHeight: .infinity, alignment: .center)
        }
        .fontWeight(.medium)
        .labelStyle(.iconOnly)
        .disabled(!self.navigator.canSelectPreviousItem)
        .help(String(localized: "Jump to previous outline item", table: "Document", comment: "tooltip for button"))
    }
    
    
    @ViewBuilder private func nextButton(systemImage: String) -> some View {
        
        Button {
            self.navigator.selectNextItem()
        } label: {
            Label(String(localized: "Next Outline Item", table: "Document", comment: "accessibility label for button"), systemImage: systemImage)
                .frame(width: 18)
                .frame(maxHeight: .infinity, alignment: .center)
        }
        .fontWeight(.medium)
        .labelStyle(.iconOnly)
        .disabled(!self.navigator.canSelectNextItem)
        .help(String(localized: "Jump to next outline item", table: "Document", comment: "tooltip for button"))
    }
}


// MARK: - Preview

#Preview {
    let navigator = OutlineNavigator()
    navigator.items = [
        OutlineItem(title: "    Heading 1", range: .notFound),
        OutlineItem(title: "Heading 2", range: .notFound),
    ]
    
    return NavigationBar(outlineNavigator: navigator, splitState: SplitState(canClose: true), tabs: PaneTabState())
        .frame(width: 300)
}
