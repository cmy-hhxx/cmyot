//
//  KeyBindingsSettingsView.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2014-08-20.
//
//  ---------------------------------------------------------------------------
//
//  © 2014-2026 1024jp
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
import AppKit
import OSLog
import Shortcut

struct KeyBindingsSettingsView: View {
    
    var usesFlexibleFrame: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var model = KeyBindingModel()
    @State private var searchText: String = ""
    @State private var onlyModified: Bool = false
    
    
    var body: some View {
        let _ = self.model.revision
        let isGlobalList = !self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || self.onlyModified
        let displayedRows = self.model.rows(searchText: self.searchText, onlyModified: self.onlyModified)
        let modifiedTotal = self.model.modifiedCount
        
        VStack(spacing: 0) {
            // Top Search & Filter Bar
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    TextField(AppLanguage.text("搜索命令或快捷键…", en: "Search commands or shortcuts…"), text: self.$searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                    
                    if !self.searchText.isEmpty {
                        Button {
                            self.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(self.colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.75)
                )
                
                HStack(spacing: 2) {
                    self.filterChip(
                        title: AppLanguage.text("全部", en: "All"),
                        isActive: !self.onlyModified
                    ) {
                        self.onlyModified = false
                    }
                    self.filterChip(
                        title: modifiedTotal > 0
                            ? AppLanguage.text("已修改 \(modifiedTotal)", en: "Modified \(modifiedTotal)")
                            : AppLanguage.text("已修改", en: "Modified"),
                        isActive: self.onlyModified
                    ) {
                        self.onlyModified = true
                    }
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.05))
                )
            }
            .padding(.horizontal, self.usesFlexibleFrame ? 16 : 20)
            .padding(.top, self.usesFlexibleFrame ? 12 : 14)
            .padding(.bottom, 10)
            
            // Middle Two-Pane Shortcut Browser & Editor (zero clipping)
            HStack(spacing: 0) {
                if !isGlobalList {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(self.model.tree.enumerated()), id: \.offset) { idx, node in
                                let isSelected = ((self.model.rootIndex ?? 0) == idx)
                                let hasModified = self.model.menuHasModified(at: idx)
                                Button {
                                    self.model.rootIndex = idx
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(node.name)
                                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                                            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.86))
                                            .lineLimit(1)
                                        Spacer(minLength: 2)
                                        if hasModified {
                                            Circle()
                                                .fill(isSelected ? Color.white.opacity(0.88) : Color.accentColor)
                                                .frame(width: 5.5, height: 5.5)
                                        }
                                    }
                                    .padding(.horizontal, 9)
                                    .frame(height: 28)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(isSelected ? Color.accentColor : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                            }
                        }
                        .padding(6)
                    }
                    .frame(width: 128)
                    .background(Color.primary.opacity(self.colorScheme == .dark ? 0.035 : 0.025))
                    
                    Rectangle()
                        .fill(Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.08))
                        .frame(width: 0.75)
                }
                
                // Command List
                if displayedRows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: self.onlyModified ? "keyboard" : "magnifyingglass")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.secondary)
                        Text(
                            self.onlyModified
                                ? AppLanguage.text("暂无自定义快捷键", en: "No Customized Shortcuts")
                                : AppLanguage.text("没有匹配的命令", en: "No Matching Commands")
                        )
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(displayedRows) { row in
                                KeyBindingCommandRowView(
                                    row: row,
                                    showMenuPrefix: isGlobalList,
                                    model: self.model
                                )
                                Rectangle()
                                    .fill(Color.primary.opacity(self.colorScheme == .dark ? 0.06 : 0.05))
                                    .frame(height: 0.5)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(self.colorScheme == .dark ? Color.white.opacity(0.03) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.primary.opacity(self.colorScheme == .dark ? 0.10 : 0.08), lineWidth: 0.75)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .padding(.horizontal, self.usesFlexibleFrame ? 16 : 20)
            .padding(.bottom, 10)
            
            Divider()
            
            // Bottom Action Bar — always crisp and unclipped
            HStack(spacing: 10) {
                Button(String(localized: "Action.restoreDefaults.label", defaultValue: "Restore Defaults"), action: self.model.restore)
                    .disabled(!self.model.isRestorable)
                    .fixedSize()
                
                Spacer(minLength: 6)
                
                if let error = self.model.error {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(error.localizedDescription)
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(.red)
                }
                
                HelpLink(anchor: "settings_keybindings")
            }
            .padding(.horizontal, self.usesFlexibleFrame ? 16 : 20)
            .frame(height: 44)
            .background(.bar)
        }
        .onAppear {
            self.model.load()
        }
        .frame(
            width: self.usesFlexibleFrame ? nil : SettingsPaneLayout.width,
            height: self.usesFlexibleFrame ? nil : SettingsPaneLayout.height
        )
        .frame(
            maxWidth: self.usesFlexibleFrame ? .infinity : nil,
            maxHeight: self.usesFlexibleFrame ? .infinity : nil
        )
        .environment(\.locale, AppLanguage.current.locale)
    }
    
    
    private func filterChip(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? (self.colorScheme == .dark ? Color.white.opacity(0.14) : Color.white) : Color.clear)
                        .shadow(color: isActive ? .black.opacity(0.08) : .clear, radius: 1.5, y: 0.5)
                )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
}


private struct KeyBindingCommandRowView: View {
    
    let row: KeyBindingModel.FlattenedCommandRow
    let showMenuPrefix: Bool
    @Bindable var model: KeyBindingModel
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    
    
    var body: some View {
        let currentShortcut = self.row.item.shortcut
        let defaultShortcut = self.row.item.defaultShortcut
        let isModified = (currentShortcut != defaultShortcut)
        let breadcrumb = self.showMenuPrefix
            ? (self.row.submenuPath.map { "\(self.row.menuName) › \($0)" } ?? self.row.menuName)
            : self.row.submenuPath
        let placeholder = defaultShortcut?.symbol ?? AppLanguage.text("点击录入", en: "Record")
        
        let shortcutBinding = Binding<Shortcut?>(
            get: { self.row.item.shortcut },
            set: { newValue in
                self.model.updateShortcut(newValue, for: self.row.item)
            }
        )
        
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if let breadcrumb, !breadcrumb.isEmpty {
                        Text(breadcrumb)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.05), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .lineLimit(1)
                    }
                    
                    Text(self.row.commandTitle)
                        .font(.system(size: 12.5, weight: isModified ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 6)
            
            if isModified {
                Button {
                    self.model.updateShortcut(defaultShortcut, for: self.row.item)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help(AppLanguage.text("恢复此项默认", en: "Reset Shortcut"))
            }
            
            if currentShortcut != nil && (self.isHovered || isModified) {
                Button {
                    self.model.updateShortcut(nil, for: self.row.item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.85))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(AppLanguage.text("清除快捷键", en: "Clear Shortcut"))
            }
            
            ShortcutField(
                value: shortcutBinding,
                error: self.$model.error,
                placeholder: placeholder,
                alignment: .center
            )
            .frame(width: 106, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isModified
                            ? Color.accentColor.opacity(self.colorScheme == .dark ? 0.16 : 0.10)
                            : Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.05)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isModified
                            ? Color.accentColor.opacity(0.55)
                            : Color.primary.opacity(self.colorScheme == .dark ? 0.14 : 0.10),
                        lineWidth: isModified ? 1.0 : 0.6
                    )
            )
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(self.isHovered ? Color.primary.opacity(self.colorScheme == .dark ? 0.05 : 0.03) : Color.clear)
        .contentShape(Rectangle())
        .onHover { inside in
            self.isHovered = inside
        }
    }
}


@MainActor @Observable private final class KeyBindingModel {
    
    typealias Item = Node<KeyBindingItem>
    
    struct FlattenedCommandRow: Identifiable {
        let id: String
        let menuIndex: Int
        let menuName: String
        let submenuPath: String?
        let commandTitle: String
        let item: KeyBindingItem
    }
    
    private(set) var tree: [Item] = []
    private(set) var isRestorable: Bool = false
    private(set) var revision: Int = 0
    var error: (any Error)?
    
    var rootIndex: Int?
    
    private let manager: KeyBindingManager = .shared
    
    
    /// Loads data from the user defaults.
    func load() {
        
        self.tree = self.manager.menuTree
        if self.rootIndex == nil && !self.tree.isEmpty {
            self.rootIndex = 0
        }
        self.isRestorable = self.manager.isCustomized
        self.revision &+= 1
    }
    
    
    /// Restores key binding setting to default.
    func restore() {
        
        try? self.manager.restoreDefaults()
        
        self.tree = self.manager.menuTree
        self.isRestorable = false
        self.error = nil
        self.revision &+= 1
    }
    
    
    func updateShortcut(_ shortcut: Shortcut?, for item: KeyBindingItem) {
        self.error = nil
        guard item.shortcut != shortcut else { return }
        item.shortcut = shortcut
        self.save()
        self.revision &+= 1
    }
    
    
    /// Saves the current settings.
    func save() {
        
        do {
            try self.manager.save(tree: self.tree)
        } catch {
            Logger.app.error("\(error.localizedDescription)")
        }
        
        self.isRestorable = self.manager.isCustomized
    }
    
    
    var modifiedCount: Int {
        self.allFlattenedRows().count { $0.item.shortcut != $0.item.defaultShortcut }
    }
    
    
    func menuHasModified(at index: Int) -> Bool {
        guard self.tree.indices.contains(index) else { return false }
        return self.tree[index].flatValues.contains { $0.shortcut != $0.defaultShortcut }
    }
    
    
    func rows(searchText: String, onlyModified: Bool) -> [FlattenedCommandRow] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isGlobal = !trimmed.isEmpty || onlyModified
        let sourceRows: [FlattenedCommandRow] = if isGlobal {
            self.allFlattenedRows()
        } else {
            self.flattenedRows(forMenuAt: self.rootIndex ?? 0)
        }
        
        return sourceRows.filter { row in
            if onlyModified && row.item.shortcut == row.item.defaultShortcut {
                return false
            }
            if !trimmed.isEmpty {
                let hay = [
                    row.menuName,
                    row.submenuPath ?? "",
                    row.commandTitle,
                    row.item.shortcut?.symbol ?? "",
                    row.item.defaultShortcut?.symbol ?? "",
                ].joined(separator: " ").lowercased()
                return hay.contains(trimmed)
            }
            return true
        }
    }
    
    
    private func allFlattenedRows() -> [FlattenedCommandRow] {
        self.tree.indices.flatMap { self.flattenedRows(forMenuAt: $0) }
    }
    
    
    private func flattenedRows(forMenuAt menuIndex: Int) -> [FlattenedCommandRow] {
        guard self.tree.indices.contains(menuIndex) else { return [] }
        let rootNode = self.tree[menuIndex]
        var result: [FlattenedCommandRow] = []
        
        func walk(_ node: Item, trail: [String]) {
            switch node.item {
                case .value(let item):
                    let path = trail.isEmpty ? nil : trail.joined(separator: " › ")
                    let rowID = "\(menuIndex):\(path ?? ""):\(node.name):\(item.action.description):\(item.tag):\(result.count)"
                    result.append(FlattenedCommandRow(
                        id: rowID,
                        menuIndex: menuIndex,
                        menuName: rootNode.name,
                        submenuPath: path,
                        commandTitle: node.name,
                        item: item
                    ))
                case .children(let children):
                    let nextTrail = trail + [node.name]
                    for child in children {
                        walk(child, trail: nextTrail)
                    }
            }
        }
        
        if let topChildren = rootNode.children {
            for child in topChildren {
                walk(child, trail: [])
            }
        }
        return result
    }
}


private struct KeyBindingTreeView: NSViewControllerRepresentable {
    
    typealias NSViewControllerType = NSViewController
    
    
    @Binding var model: KeyBindingModel
    
    
    func makeNSViewController(context: Context) -> NSViewController {
        
        NSStoryboard(name: "KeyBindingTreeView", bundle: nil).instantiateInitialController { coder in
            KeyBindingTreeViewController(model: self.model, coder: coder)
        }!
    }
    
    
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
        
    }
}


// MARK: -

/// Column identifiers for outline view.
private extension NSUserInterfaceItemIdentifier {
    
    static let command = NSUserInterfaceItemIdentifier("command")
    static let key = NSUserInterfaceItemIdentifier("key")
}


final class KeyBindingTreeViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    
    // MARK: Private Properties
    
    private let model: KeyBindingModel
    
    @IBOutlet private weak var listView: NSTableView?
    @IBOutlet private weak var outlineView: NSOutlineView?
    
    
    // MARK: Lifecycle
    
    fileprivate init?(model: KeyBindingModel, coder: NSCoder) {
        
        self.model = model
        
        super.init(coder: coder)
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.listView?.rowSizeStyle = .medium
        self.outlineView?.rowSizeStyle = .medium
    }
    
    
    override func viewWillAppear() {
        
        super.viewWillAppear()
        
        self.listView?.reloadData()
        self.outlineView?.reloadData()
        
        self.observe()
    }
    
    
    // MARK: Outline View Data Source
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        
        if let node = item as? Node<KeyBindingItem> {
            node.children?.count ?? 0
        } else if let rootIndex = self.model.rootIndex, rootIndex >= 0 {
            self.model.tree[rootIndex].children?.count ?? 0
        } else {
            0
        }
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        
        (item as? Node<KeyBindingItem>)?.children != nil
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        
        if let node = item as? Node<KeyBindingItem> {
            node.children![index]
        } else if let rootIndex = self.model.rootIndex {
            self.model.tree[rootIndex].children![index]
        } else {
            preconditionFailure()
        }
    }
    
    
    // MARK: Outline View Delegate
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        
        guard
            let node = item as? Node<KeyBindingItem>,
            let identifier = tableColumn?.identifier,
            let cellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
        else { return nil }
        
        switch identifier {
            case .command:
                cellView.objectValue = node.name
                
            case .key:
                switch node.item {
                    case .value(let item):
                        cellView.objectValue = item.shortcut
                        cellView.textField?.placeholderString = item.defaultShortcut?.symbol
                        
                    case .children:
                        cellView.textField?.isEditable = false
                }
                
            default:
                preconditionFailure()
        }
        
        return cellView
    }
    
    
    // MARK: Action Messages
    
    /// Validates and apply new shortcut key input.
    @IBAction func didEditShortcut(_ sender: ShortcutTextField) {
        
        guard let outlineView = self.outlineView else { return assertionFailure() }
        
        let row = outlineView.row(for: sender)
        let column = outlineView.column(for: sender)
        
        guard
            let node = outlineView.item(atRow: row) as? Node<KeyBindingItem>,
            let item = node.value
        else { return }
        
        let oldShortcut = item.shortcut
        let shortcut = sender.objectValue as? Shortcut
        
        // reset once warning
        self.model.error = nil
        
        // not edited
        guard shortcut != oldShortcut else { return }
        
        if let shortcut {
            do {
                try shortcut.checkCustomizationAvailability(for: NSApp.mainMenu)
            } catch {
                self.model.error = error
                sender.objectValue = oldShortcut  // reset text field
                NSSound.beep()
                
                // make text field edit mode again
                Task {
                    outlineView.editColumn(column, row: row, with: nil, select: true)
                }
                return
            }
        }
        
        // successfully update data
        item.shortcut = shortcut
        self.model.save()
        outlineView.reloadData(forRowIndexes: [row], columnIndexes: [column])
    }
    
    
    // MARK: Private Methods
    
    /// Recursively observes the `.isRestorable` flag.
    private func observe() {
        
        withObservationTracking {
            if self.model.isRestorable == false {
                self.outlineView?.reloadData()
            }
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observe()
            }
        }
    }
}


extension KeyBindingTreeViewController: NSTableViewDataSource, NSTableViewDelegate {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        
        self.model.tree.count
    }
    
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        
        self.model.tree[row].name
    }
    
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        
        guard let tableView = notification.object as? NSTableView else { return }
        
        tableView.window?.makeFirstResponderDiscardingMarkedText(nil)
        self.model.rootIndex = tableView.selectedRow
        self.outlineView?.reloadData()
    }
}


// MARK: - Preview

#Preview {
    KeyBindingsSettingsView()
}
