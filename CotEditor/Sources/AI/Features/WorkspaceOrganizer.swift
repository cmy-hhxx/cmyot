//
//  WorkspaceOrganizer.swift
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
import Foundation
import StringUtils

/// Coordinates one-click AI organization and merging across every open window and pane.
@MainActor
enum WorkspaceOrganizer {
    
    // MARK: Types
    
    struct SourceEntry {
        let id: String
        let windowIndex: Int
        let paneIndex: Int
        let originalTitle: String
        let fileURL: URL?
        let syntaxName: String
        let content: String
        weak var windowVC: DocumentViewController?
        weak var pane: EditorViewController?
        weak var tab: PaneTab?
        weak var document: Document?
        
        var locationLabel: String {
            "窗口 \(self.windowIndex) · 分栏 \(self.paneIndex)"
        }
    }
    
    struct MergePlan: Decodable {
        struct Group: Decodable {
            let newTitle: String
            let syntax: String?
            let summary: String?
            let sourceIDs: [String]
            let mergedContent: String
        }
        
        struct MappingRow: Decodable {
            let sourceID: String?
            let sourceTitle: String
            let action: String
            let targetTitle: String
            let note: String?
        }
        
        let overview: String?
        let groups: [Group]
        let mapping: [MappingRow]?
    }
    
    
    // MARK: Public Actions
    
    /// Safely renames either an untitled tab/document or a saved file on disk, keeping extension and updating DB.
    ///
    /// - Returns: The resulting display title if renaming succeeded.
    @discardableResult
    static func renameDocument(_ document: Document, to rawNewName: String) throws -> String {
        
        let trimmed = rawNewName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else {
            throw NSError(
                domain: "CotWorkspaceOrganizer",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "文件名不能为空或包含非法路径字符。"]
            )
        }
        
        let rawDocID = document.databaseDocumentID.hasPrefix("doc:") ? document.databaseDocumentID : "doc:\(document.databaseDocumentID)"
        
        if let currentURL = document.fileURL {
            let oldPath = currentURL.path(percentEncoded: false)
            let parentDir = currentURL.deletingLastPathComponent()
            let existingExt = currentURL.pathExtension
            let hasExplicitExt = !(trimmed as NSString).pathExtension.isEmpty
            let baseFilename = (!existingExt.isEmpty && !hasExplicitExt) ? "\(trimmed).\(existingExt)" : trimmed
            
            var targetURL = parentDir.appending(path: baseFilename)
            if targetURL.standardizedFileURL == currentURL.standardizedFileURL {
                return currentURL.lastPathComponent
            }
            
            // Avoid overwriting an unrelated existing file on disk.
            if FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false)) {
                let stem = (baseFilename as NSString).deletingPathExtension
                let ext = (baseFilename as NSString).pathExtension
                var suffix = 2
                while FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false)) {
                    let candidate = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
                    targetURL = parentDir.appending(path: candidate)
                    suffix += 1
                }
            }
            
            try FileManager.default.moveItem(at: currentURL, to: targetURL)
            document.fileURL = targetURL
            let newPath = targetURL.path(percentEncoded: false)
            NotificationCenter.default.post(name: NSDocument.DidChangeFileURLMessage.name, object: document)
            CotLocalDatabase.shared.renameDocument(oldID: oldPath, newID: newPath, newTitle: targetURL.lastPathComponent, newFilePath: newPath)
            return targetURL.lastPathComponent
        } else {
            document.displayName = trimmed
            NotificationCenter.default.post(name: NSDocument.DidChangeFileURLMessage.name, object: document)
            CotLocalDatabase.shared.renameDocument(oldID: rawDocID, newID: rawDocID, newTitle: trimmed, newFilePath: nil)
            document.syncToLocalDatabase()
            return trimmed
        }
    }
    
    
    /// Runs AI organize-and-merge across all open windows/documents and creates a formatted Map document.
    static func runOrganizeAndMerge(from anchorWindow: NSWindow?) {
        
        let entries = self.collectOpenDocuments()
        guard !entries.isEmpty else {
            let alert = NSAlert()
            alert.messageText = String(localized: "ai.organizeMerge.empty.title",
                                       defaultValue: "没有可整理的非空文档", table: "AI")
            alert.informativeText = String(localized: "ai.organizeMerge.empty.message",
                                           defaultValue: "请先在窗口中打开或输入一些文档内容，然后再执行一键整理合并。", table: "AI")
            if let anchorWindow {
                alert.beginSheetModal(for: anchorWindow)
            } else {
                alert.runModal()
            }
            return
        }
        
        guard AIService.shared.isConfigured else {
            let alert = NSAlert()
            alert.messageText = String(localized: "chrome.aiAlert.title",
                                       defaultValue: "AI Is Not Configured", table: "Chrome")
            alert.informativeText = String(localized: "chrome.aiAlert.message",
                                           defaultValue: "Set the endpoint, model, and API key in Settings before using AI features.", table: "Chrome")
            alert.addButton(withTitle: String(localized: "chrome.aiAlert.openSettings",
                                              defaultValue: "Open AI Settings", table: "Chrome"))
            alert.addButton(withTitle: String(localized: "chrome.alert.cancel",
                                              defaultValue: "Cancel", table: "Chrome"))
            if let anchorWindow {
                alert.beginSheetModal(for: anchorWindow) { response in
                    if response == .alertFirstButtonReturn {
                        (NSApp.delegate as? AppDelegate)?.showAIPreferences(nil)
                    }
                }
            } else if alert.runModal() == .alertFirstButtonReturn {
                (NSApp.delegate as? AppDelegate)?.showAIPreferences(nil)
            }
            return
        }
        
        // Snapshot every document into local SQLite before any destructive or merge operation.
        for entry in entries {
            guard let doc = entry.document else { continue }
            doc.syncToLocalDatabase()
        }
        
        let compiledPrompt = self.buildPrompt(from: entries)
        
        let panel = AIResultPanelController(action: .organizeAndMerge)
        if let targetWindow = anchorWindow ?? NSApp.mainWindow ?? NSApp.orderedWindows.first {
            panel.present(on: targetWindow)
        }
        
        Task {
            do {
                let rawResponse = try await AIService.shared.run(.organizeAndMerge, on: compiledPrompt) { partial in
                    panel.presentPartial(result: "正在分析全工作区 \(entries.count) 份文档并归类合并...\n\n\(partial)")
                }
                
                let plan = try self.decodePlan(from: rawResponse)
                let mapMarkdown = self.apply(plan: plan, entries: entries)
                
                // Close progress sheet cleanly and present the newly generated Map document.
                if let sheetWindow = panel.window, let parent = sheetWindow.sheetParent {
                    parent.endSheet(sheetWindow)
                } else {
                    panel.close()
                }
                
                let mapDoc = try (NSDocumentController.shared as? DocumentController)?
                    .openUntitledDocument(content: mapMarkdown, title: "整理合并 Map", display: true)
                mapDoc?.setSyntax(name: SyntaxName.markdown)
                mapDoc?.syncToLocalDatabase()
                
                for window in NSApp.orderedWindows {
                    (window.windowController as? DocumentWindowController)?
                        .documentViewController?
                        .savePaneTabsSessionToDatabase()
                }
            } catch {
                panel.present(error: error)
            }
        }
    }
    
    
    // MARK: Internal Helpers (Exposed for Testing)
    
    /// Decodes a `MergePlan` JSON response, stripping surrounding Markdown code fences or leading prose.
    static func decodePlan(from rawResponse: String) throws -> MergePlan {
        
        let trimmed = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateString: String
        
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start <= end {
            candidateString = String(trimmed[start...end])
        } else {
            candidateString = trimmed
        }
        
        guard let data = candidateString.data(using: .utf8) else {
            throw NSError(
                domain: "CotWorkspaceOrganizer",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "AI 返回的整理方案无法编码为 UTF-8。"]
            )
        }
        
        let plan = try JSONDecoder().decode(MergePlan.self, from: data)
        guard !plan.groups.isEmpty else {
            throw NSError(
                domain: "CotWorkspaceOrganizer",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "AI 返回的分组列表为空，未做任何修改。"]
            )
        }
        return plan
    }
    
    
    /// Builds a structured Map document from a parsed merge plan.
    static func renderMapMarkdown(
        overview: String?,
        mappingRows: [(originalTitle: String, location: String, action: String, newTitle: String, note: String)],
        groups: [(title: String, syntax: String, summary: String)],
        untouchedEntries: [SourceEntry]
    ) -> String {
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let timestamp = formatter.string(from: Date())
        
        var lines: [String] = [
            "# 文档整理合并 Map",
            "",
            "> 整理时间：\(timestamp)",
        ]
        if let overview, !overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("> 总结：\(overview.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        lines.append("")
        lines.append("## 一、合并前后文档映射表")
        lines.append("")
        lines.append("| 原文档 | 来源位置 | 处理方式 | 合并后标题 | 说明 |")
        lines.append("| :--- | :--- | :--- | :--- | :--- |")
        
        func esc(_ text: String) -> String {
            text.replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        for row in mappingRows {
            lines.append("| \(esc(row.originalTitle)) | \(esc(row.location)) | \(esc(row.action)) | \(esc(row.newTitle)) | \(esc(row.note)) |")
        }
        for entry in untouchedEntries {
            lines.append("| \(esc(entry.originalTitle)) | \(esc(entry.locationLabel)) | 保持原样 | \(esc(entry.originalTitle)) | 未被归入合并分组，原内容保留 |")
        }
        
        lines.append("")
        lines.append("## 二、整理后文档目录（共 \(groups.count) 份）")
        lines.append("")
        for (idx, group) in groups.enumerated() {
            let summaryText = group.summary.isEmpty ? "内容已去重并重新排版。" : group.summary
            lines.append("\(idx + 1). **\(group.title)**（`\(group.syntax)`）— \(summaryText)")
        }
        
        lines.append("")
        lines.append("---")
        lines.append("> 数据安全说明：合并前的所有非空文档快照已备份至本地 SQLite 数据库（设置 → AI → 查看已存文档），涉及的磁盘原文件不会被自动删除。")
        lines.append("")
        
        return MarkdownTableFormatter.formatTables(in: lines.joined(separator: "\n"))
    }
    
    
    // MARK: Private Implementation
    
    private static func collectOpenDocuments() -> [SourceEntry] {
        
        var result: [SourceEntry] = []
        var seenDocIDs = Set<ObjectIdentifier>()
        var counter = 0
        
        let windowControllers = NSApp.orderedWindows
            .compactMap { $0.windowController as? DocumentWindowController }
        
        for (winIdx, wc) in windowControllers.enumerated() {
            guard let docVC = wc.documentViewController else { continue }
            for (paneIdx, pane) in docVC.editorViewControllers.enumerated() {
                for tab in pane.tabs {
                    let doc = tab.document
                    let objID = ObjectIdentifier(doc)
                    guard seenDocIDs.insert(objID).inserted else { continue }
                    
                    let content = doc.textStorage.string
                    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    
                    counter += 1
                    result.append(SourceEntry(
                        id: "doc_\(counter)",
                        windowIndex: winIdx + 1,
                        paneIndex: paneIdx + 1,
                        originalTitle: doc.displayName,
                        fileURL: doc.fileURL,
                        syntaxName: doc.syntaxName,
                        content: content,
                        windowVC: docVC,
                        pane: pane,
                        tab: tab,
                        document: doc
                    ))
                }
            }
        }
        
        return result
    }
    
    
    private static func buildPrompt(from entries: [SourceEntry]) -> String {
        
        var parts: [String] = [
            "当前共有 \(entries.count) 份非空打开文档，请识别相似内容并合并、去重、重命名、工整排版："
        ]
        
        for entry in entries {
            let fileDesc = entry.fileURL?.path(percentEncoded: false) ?? "未保存临时文档"
            // Cap overly huge individual files softly while preserving full note contents
            let clipped = String(entry.content.prefix(18_000))
            parts.append("""
            ---
            ID: \(entry.id)
            原文档名: \(entry.originalTitle)
            位置: \(entry.locationLabel)
            文件路径: \(fileDesc)
            当前语法: \(entry.syntaxName)
            正文:
            \(clipped)
            """)
        }
        
        return parts.joined(separator: "\n\n")
    }
    
    
    private static func apply(plan: MergePlan, entries: [SourceEntry]) -> String {
        
        let entryByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        var consumedIDs = Set<String>()
        var mappingRows: [(originalTitle: String, location: String, action: String, newTitle: String, note: String)] = []
        var createdGroups: [(title: String, syntax: String, summary: String)] = []
        
        // Map model-supplied mapping notes by sourceID/sourceTitle for rich explanations.
        var noteBySourceID: [String: String] = [:]
        for row in plan.mapping ?? [] {
            if let sourceID = row.sourceID, let note = row.note, !note.isEmpty {
                noteBySourceID[sourceID] = note
            }
        }
        
        for group in plan.groups {
            let resolvedSyntax = self.normalizedSyntaxName(group.syntax)
            let formattedContent = MarkdownTableFormatter.formatTables(in: group.mergedContent)
                .trimmingCharacters(in: .newlines) + "\n"
            
            let matchingEntries = group.sourceIDs.compactMap { entryByID[$0] }.filter { !consumedIDs.contains($0.id) }
            
            // Prefer an existing untitled document or primary entry to host the merged document.
            let primaryEntry = matchingEntries.first(where: { $0.fileURL == nil }) ?? matchingEntries.first
            var finalTitle = group.newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if finalTitle.isEmpty {
                finalTitle = primaryEntry?.originalTitle ?? "整理合并文档"
            }
            
            if let primary = primaryEntry, let doc = primary.document {
                consumedIDs.insert(primary.id)
                
                if let renamed = try? self.renameDocument(doc, to: finalTitle) {
                    finalTitle = renamed
                }
                doc.setSyntax(name: resolvedSyntax)
                
                // Replace document text cleanly via the text view when available so Undo still works.
                if let tv = primary.pane?.textView(for: primary.tab ?? PaneTab(document: doc)) {
                    tv.insertText(formattedContent, replacementRange: doc.textStorage.range)
                } else {
                    doc.textStorage.replaceCharacters(in: doc.textStorage.range, with: formattedContent)
                }
                doc.syncToLocalDatabase()
                
                let actionLabel = matchingEntries.count > 1 ? "主合并并重命名" : "整理并重命名"
                let defaultNote = matchingEntries.count > 1
                    ? "吸收并合并了 \(matchingEntries.count) 份相似文档，已去重排版"
                    : (group.summary ?? "优化命名并重新排版")
                mappingRows.append((
                    originalTitle: primary.originalTitle,
                    location: primary.locationLabel,
                    action: actionLabel,
                    newTitle: finalTitle,
                    note: noteBySourceID[primary.id] ?? defaultNote
                ))
                
                // Handle secondary source tabs merged into the primary document.
                for secondary in matchingEntries where secondary.id != primary.id {
                    consumedIDs.insert(secondary.id)
                    if let secDoc = secondary.document,
                       secDoc.fileURL == nil,
                       let secTab = secondary.tab,
                       let secPane = secondary.pane,
                       let secWinVC = secondary.windowVC,
                       secWinVC.closeMergedTabSafely(secTab, in: secPane)
                    {
                        mappingRows.append((
                            originalTitle: secondary.originalTitle,
                            location: secondary.locationLabel,
                            action: "已并入并关闭重复标签",
                            newTitle: finalTitle,
                            note: noteBySourceID[secondary.id] ?? "内容已去重并入「\(finalTitle)」"
                        ))
                    } else {
                        mappingRows.append((
                            originalTitle: secondary.originalTitle,
                            location: secondary.locationLabel,
                            action: "已并入（原文件保留）",
                            newTitle: finalTitle,
                            note: noteBySourceID[secondary.id] ?? "内容已并入「\(finalTitle)」，原文件安全保留未删"
                        ))
                    }
                }
            } else if let opened = try? (NSDocumentController.shared as? DocumentController)?
                .openUntitledDocument(content: formattedContent, title: finalTitle, display: true)
            {
                opened.setSyntax(name: resolvedSyntax)
                opened.syncToLocalDatabase()
                createdGroups.append((title: finalTitle, syntax: resolvedSyntax, summary: group.summary ?? ""))
                continue
            }
            
            createdGroups.append((title: finalTitle, syntax: resolvedSyntax, summary: group.summary ?? ""))
        }
        
        let untouched = entries.filter { !consumedIDs.contains($0.id) }
        return self.renderMapMarkdown(
            overview: plan.overview,
            mappingRows: mappingRows,
            groups: createdGroups,
            untouchedEntries: untouched
        )
    }
    
    
    private static func normalizedSyntaxName(_ raw: String?) -> String {
        
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return SyntaxName.markdown
        }
        if raw.contains("plain") || raw.contains("纯文本") {
            return SyntaxName.none
        }
        return SyntaxName.markdown
    }
}
