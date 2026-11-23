//
//  PaneTab.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-11-05.
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
import Observation

/// Where a dragged pane tab will land when dropped onto an editor pane.
enum PaneDropZone: Equatable {
    
    case center
    case left
    case right
    case top
    case bottom
    
    static func from(point: NSPoint, in bounds: NSRect) -> PaneDropZone {
        
        // Dragging a document onto another pane only moves the tab into that pane;
        // splitting is reserved strictly for explicit ⌃A % / ⌃A " commands.
        .center
    }
}


/// One document a pane shows, drawn as a tab in the pane's tab bar.
@Observable final class PaneTab {
    
    static let dragPrefix = "cot-pane-tab:"
    static let dragPasteboardType = NSPasteboard.PasteboardType("local.cmy.CotEditor.paneTab")
    
    /// A stable identity used while dragging a tab around the bar.
    let id = UUID()
    
    /// The string payload placed on the drag pasteboard for cross-pane and cross-window drops.
    var dragPayload: String {
        
        Self.dragPrefix + self.id.uuidString
    }
    
    /// Extracts a `PaneTab` UUID from a drag payload string.
    static func tabID(from payload: String) -> UUID? {
        
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(Self.dragPrefix) {
            return UUID(uuidString: String(trimmed.dropFirst(Self.dragPrefix.count)))
        }
        return UUID(uuidString: trimmed)
    }
    
    /// The document this tab shows.
    let document: Document
    
    /// Whether the tab is pinned.
    ///
    /// A pinned tab cannot be closed, and stays anchored at the front of the tab bar.
    var isPinned = false
    
    /// Whether the tab can be closed at all.
    var isClosable = true
    
    /// Optional interactive board state when this tab has been converted into a dashboard module.
    var boardState: PaneBoardState?
    
    /// Whether this tab currently hosts a modular board instead of a text editor.
    var isBoard: Bool { self.boardState != nil }
    
    /// SF Symbol shown on the tab when hosting a modular board.
    var boardSymbolName: String? { self.boardState?.kind.symbolName }
    
    
    /// The title shown on the tab.
    var title: String {
        
        if let board = self.boardState {
            let dynamic = board.dynamicTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return dynamic.isEmpty ? board.kind.title : dynamic
        }
        return self.document.displayName
    }
    
    
    /// Whether the document behind the tab has unsaved changes.
    var isEdited: Bool {
        
        if self.isBoard { return false }
        return self.document.hasUncommittedChanges || self.document.isDocumentEdited
    }
    
    
    init(document: Document) {
        
        self.document = document
    }
}


/// The state a pane's tab bar renders, plus the commands the bar sends back to the pane.
@Observable final class PaneTabState {
    
    /// The tabs in visual order.
    var tabs: [PaneTab] = []
    
    /// The tab whose document is currently shown in the pane.
    var selectedTab: PaneTab?
    
    /// Whether the whole pane can be closed (i.e. the window is split).
    var canClosePane = false
    
    /// Incremented whenever a tab's title or edited state updates so SwiftUI/AppKit views refresh cleanly.
    var refreshRevision: Int = 0
    
    var onSelect: (PaneTab) -> Void = { _ in }
    var onSelectForRename: (PaneTab) -> Void = { _ in }
    var onClose: (PaneTab) -> Void = { _ in }
    var onNewTab: () -> Void = {}
    var onTogglePin: (PaneTab) -> Void = { _ in }
    var onRename: (PaneTab, String) -> Void = { _, _ in }
    var onMove: (PaneTab, PaneTab) -> Void = { _, _ in }
    var onMoveToIndex: (PaneTab, Int) -> Void = { _, _ in }
    var onDropTab: (UUID, Int?) -> Bool = { _, _ in false }
    var onDetachToNewWindow: (PaneTab, NSPoint) -> Void = { _, _ in }
    var onClosePane: () -> Void = {}
    var onRequestInlineRename: ((PaneTab) -> Void)?
    var onConvertTabToBoard: (PaneTab, PaneBoardKind) -> Void = { _, _ in }
    var onRevertBoardToDocument: (PaneTab) -> Void = { _ in }
    var onNewBoardTab: (PaneBoardKind) -> Void = { _ in }
}
