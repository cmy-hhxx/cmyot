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

/// One document a pane shows, drawn as a tab in the pane's tab bar.
@Observable final class PaneTab {
    
    /// A stable identity used while dragging a tab around the bar.
    let id = UUID()
    
    /// The document this tab shows.
    let document: Document
    
    /// Whether the tab is pinned.
    ///
    /// A pinned tab cannot be closed, and shrinks to an accent-colored pin so it takes
    /// almost no width in the bar — the same way a pinned browser tab does.
    var isPinned = false
    
    /// Whether the tab can be closed at all.
    ///
    /// The tab showing the window's own document stays unclosable, because the window has
    /// no way to display any other document.
    var isClosable = true
    
    
    /// The title shown on the tab.
    var title: String {
        
        self.document.displayName
    }
    
    
    /// Whether the document behind the tab has unsaved changes.
    var isEdited: Bool {
        
        self.document.isDocumentEdited
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
    
    var onSelect: (PaneTab) -> Void = { _ in }
    var onClose: (PaneTab) -> Void = { _ in }
    var onNewTab: () -> Void = {}
    var onTogglePin: (PaneTab) -> Void = { _ in }
    var onMove: (PaneTab, PaneTab) -> Void = { _, _ in }
    var onClosePane: () -> Void = {}
}
