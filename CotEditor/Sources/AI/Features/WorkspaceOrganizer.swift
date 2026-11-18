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
    /// Resolves a user-supplied filename while keeping the source extension intact when the new name omits one
    /// or contains dots such as version numbers / dates (`2026.11 周报`).
    static func resolvedRenamedFilename(for trimmed: String, preservingExtensionOf currentURL: URL) -> String {
        
        let existingExt = currentURL.pathExtension
        guard !existingExt.isEmpty else { return trimmed }
        if trimmed.lowercased().hasSuffix(".\(existingExt.lowercased())") {
            return trimmed
        }
        
        let candidateExt = (trimmed as NSString).pathExtension
        let isPlausibleExtension = !candidateExt.isEmpty
            && candidateExt.count <= 8
            && !candidateExt.contains(where: \.isWhitespace)
            && candidateExt.contains(where: \.isLetter)
            && candidateExt.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return isPlausibleExtension ? trimmed : "\(trimmed).\(existingExt)"
    }
    
    
    /// Moves a file safely using `NSFileCoordinator` and returns the destination URL with collision avoidance.
    static func coordinatedMoveFile(
        from sourceURL: URL,
        toDesiredFilename desiredName: String,
        filePresenter: (any NSFilePresenter)? = nil
    ) throws -> URL {
        
        let parentDir = sourceURL.deletingLastPathComponent()
        var targetURL = parentDir.appending(path: desiredName)
        if targetURL.standardizedFileURL == sourceURL.standardizedFileURL {
            return sourceURL
        }
        
        if FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false)) {
            let stem = (desiredName as NSString).deletingPathExtension
            let ext = (desiredName as NSString).pathExtension
            var suffix = 2
            while FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false)) {
                let candidate = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
                targetURL = parentDir.appending(path: candidate)
                suffix += 1
            }
        }
        
        var coordinatorError: NSError?
        var moveError: (any Error)?
        let coordinator = NSFileCoordinator(filePresenter: filePresenter)
        coordinator.coordinate(
            writingItemAt: sourceURL,
            options: .forMoving,
            writingItemAt: targetURL,
            options: .forReplacing,
            error: &coordinatorError
        ) { newSource, newDest in
            do {
                try FileManager.default.moveItem(at: newSource, to: newDest)
                coordinator.item(at: newSource, didMoveTo: newDest)
            } catch {
                moveError = error
            }
        }
        
        if let coordinatorError {
            CotLogger.shared.error(category: .document, "Coordinated file rename failed", error: coordinatorError)
            throw coordinatorError
        }
        if let moveError {
            CotLogger.shared.error(category: .document, "File rename move failed", error: moveError)
            throw moveError
        }
        
        return targetURL
    }
    
    
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
            let baseFilename = Self.resolvedRenamedFilename(for: trimmed, preservingExtensionOf: currentURL)
            let targetURL = try Self.coordinatedMoveFile(
                from: currentURL,
                toDesiredFilename: baseFilename,
                filePresenter: document
            )
            
            document.fileURL = targetURL
            document.displayName = targetURL.lastPathComponent
            document.isExplicitlyNamed = true
            document.invalidateSyntax(filename: targetURL.lastPathComponent)
            
            let newPath = targetURL.path(percentEncoded: false)
            CotLocalDatabase.shared.renameDocument(
                oldID: oldPath,
                oldFilePath: oldPath,
                newID: newPath,
                newTitle: targetURL.lastPathComponent,
                newFilePath: newPath
            )
            // Migrate any pre-save untitled DB record into this file-backed row so no stale duplicate lingers.
            if CotLocalDatabase.shared.documents.contains(where: { $0.id == rawDocID }) {
                CotLocalDatabase.shared.renameDocument(
                    oldID: rawDocID,
                    oldFilePath: nil,
                    newID: newPath,
                    newTitle: targetURL.lastPathComponent,
                    newFilePath: newPath
                )
            }
            document.syncToLocalDatabase(force: true)
            NotificationCenter.default.post(name: NSDocument.DidChangeFileURLMessage.name, object: document)
            return targetURL.lastPathComponent
        } else {
            document.displayName = trimmed
            document.isExplicitlyNamed = true
            CotLocalDatabase.shared.renameDocument(
                oldID: rawDocID,
                oldFilePath: nil,
                newID: rawDocID,
                newTitle: trimmed,
                newFilePath: nil
            )
            document.syncToLocalDatabase(force: true)
            NotificationCenter.default.post(name: NSDocument.DidChangeFileURLMessage.name, object: document)
            return trimmed
        }
    }
    
    
    private static var activeProgressController: WorkspaceOrganizeProgressController?
    private static var activeOrganizeTask: Task<Void, Never>?
    
    
    /// Runs AI organize-and-merge across all open windows/documents and creates a formatted Map document.
    static func runOrganizeAndMerge(from anchorWindow: NSWindow?) {
        
        self.activeOrganizeTask?.cancel()
        self.activeOrganizeTask = nil
        self.activeProgressController?.dismissSheet()
        self.activeProgressController = nil
        
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
        
        let targetWindow = anchorWindow ?? NSApp.mainWindow ?? NSApp.orderedWindows.first
        let profileDesc: String = {
            if let profile = AIEndpointStore.activeProfile {
                let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
                return model.isEmpty ? profile.displayName : "\(profile.displayName) · \(model)"
            }
            return "AI"
        }()
        let progressController = WorkspaceOrganizeProgressController(
            totalDocumentCount: entries.count,
            endpointDescription: profileDesc
        )
        self.activeProgressController = progressController
        progressController.onDismiss = { [weak progressController] in
            if Self.activeProgressController === progressController {
                Self.activeProgressController = nil
            }
            Self.activeOrganizeTask = nil
        }
        progressController.onRetry = { [weak targetWindow] in
            Task { @MainActor in
                Self.runOrganizeAndMerge(from: targetWindow)
            }
        }
        progressController.present(on: targetWindow)
        
        // Step 1: Snapshot every document into local SQLite before any modification.
        progressController.state.markStepActive(
            0,
            detail: "正在备份 \(entries.count) 份文档快照到本地数据库…",
            progress: 0.12,
            headline: "步骤 1/4：备份当前文档快照"
        )
        for entry in entries {
            guard let doc = entry.document else { continue }
            doc.syncToLocalDatabase(force: true)
        }
        progressController.state.markStepCompleted(0, detail: "已安全备份 \(entries.count) 份文档快照")
        
        let compiledPrompt = self.buildPrompt(from: entries)
        
        progressController.state.markStepActive(
            1,
            detail: "正在发送 \(entries.count) 份文档至 AI 分析去重与拟定文件名…",
            progress: 0.25,
            headline: "步骤 2/4：AI 归类分析与内容提炼"
        )
        
        let organizeTask = Task { @MainActor in
            do {
                let rawResponse = try await AIService.shared.run(.organizeAndMerge, on: compiledPrompt) { partial in
                    let charCount = partial.count
                    progressController.state.streamedCharacters = charCount
                    let streamProgress = 0.25 + min(0.47, Double(charCount) / 8000.0 * 0.47)
                    progressController.state.markStepActive(
                        1,
                        detail: "已接收模型整理方案 \(charCount) 字…",
                        progress: streamProgress,
                        headline: "步骤 2/4：正在接收 AI 归类与命名方案"
                    )
                }
                
                guard !Task.isCancelled else { return }
                progressController.state.markStepCompleted(
                    1,
                    detail: "AI 分析完成（共 \(rawResponse.count) 字）"
                )
                
                progressController.state.markStepActive(
                    2,
                    detail: "正在按文档内容重命名并排版（保持原有分屏 Pane 不变）…",
                    progress: 0.78,
                    headline: "步骤 3/4：原位更新文档与智能重命名"
                )
                
                let plan = try self.decodePlan(from: rawResponse)
                let outcome = self.apply(plan: plan, entries: entries)
                
                progressController.state.markStepCompleted(
                    2,
                    detail: "已更新 \(outcome.updatedCount) 份文档并重命名，原有分屏 Pane 完整保留"
                )
                
                progressController.state.markStepActive(
                    3,
                    detail: "正在生成《整理合并 Map》总览文档…",
                    progress: 0.92,
                    headline: "步骤 4/4：生成整理合并 Map"
                )
                
                if let hostDocVC = (targetWindow?.windowController as? DocumentWindowController)?.documentViewController {
                    hostDocVC.openGeneratedTab(
                        title: "整理合并 Map.md",
                        content: outcome.mapMarkdown,
                        syntaxName: SyntaxName.markdown,
                        databaseID: "organize-map:latest"
                    )
                } else {
                    let mapDoc = try (NSDocumentController.shared as? DocumentController)?
                        .openUntitledDocument(content: outcome.mapMarkdown, title: "整理合并 Map.md", display: true)
                    mapDoc?.isExplicitlyNamed = true
                    mapDoc?.setSyntax(name: SyntaxName.markdown)
                    mapDoc?.syncToLocalDatabase(force: true)
                }
                
                for window in NSApp.orderedWindows {
                    guard let docVC = (window.windowController as? DocumentWindowController)?.documentViewController else { continue }
                    for pane in docVC.editorViewControllers {
                        pane.updateTabState()
                    }
                    window.windowController?.synchronizeWindowTitleWithDocumentName()
                    docVC.savePaneTabsSessionToDatabase()
                }
                
                progressController.state.markStepCompleted(3, detail: "已生成并在当前焦点 Pane 中打开《整理合并 Map》")
                progressController.state.markCompleted(
                    summary: "整理完成：共处理 \(outcome.updatedCount) 组文档、重命名 \(outcome.renamedCount) 份文件/标签页，原有窗口与分屏 Pane 布局未作任何破坏性变动。"
                )
            } catch is CancellationError {
                CotLogger.shared.info(category: .organizer, "Organize & Merge cancelled by user")
            } catch {
                CotLogger.shared.error(category: .organizer, "Organize & Merge failed", error: error)
                progressController.state.markFailed(message: error.localizedDescription)
            }
        }
        
        self.activeOrganizeTask = organizeTask
        progressController.onCancel = {
            organizeTask.cancel()
            Self.activeOrganizeTask = nil
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
            lines.append("\(idx + 1). \(group.title)（\(group.syntax)）— \(summaryText)")
        }
        
        lines.append("")
        lines.append("## 三、数据安全说明")
        lines.append("")
        lines.append("合并前的所有非空文档快照已备份至本地 SQLite 数据库（设置 → AI → 查看已存文档），涉及的磁盘原文件不会被自动删除。")
        lines.append("")
        
        return AIDocumentTextCleaner.clean(lines.joined(separator: "\n")) + "\n"
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
    
    
    struct ApplyOutcome {
        let mapMarkdown: String
        let updatedCount: Int
        let renamedCount: Int
    }
    
    
    /// Derives a concise, content-representative title when AI returns an empty or generic/random title.
    static func fallbackContentTitle(from content: String, currentTitle: String) -> String {
        
        for rawLine in content.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#") {
                line = String(line.drop(while: { $0 == "#" || $0 == " " }))
            }
            line = line
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .replacingOccurrences(of: "|", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasSuffix("：") || line.hasSuffix(":") {
                line.removeLast()
            }
            if !line.isEmpty {
                return line.count > 22 ? String(line.prefix(22)).trimmingCharacters(in: .whitespacesAndNewlines) : line
            }
        }
        return currentTitle.isEmpty ? "整理文档" : currentTitle
    }
    
    
    private static func apply(plan: MergePlan, entries: [SourceEntry]) -> ApplyOutcome {
        
        let entryByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        var consumedIDs = Set<String>()
        var mappingRows: [(originalTitle: String, location: String, action: String, newTitle: String, note: String)] = []
        var createdGroups: [(title: String, syntax: String, summary: String)] = []
        var updatedCount = 0
        var renamedCount = 0
        
        // Map model-supplied mapping notes by sourceID/sourceTitle for rich explanations.
        var noteBySourceID: [String: String] = [:]
        for row in plan.mapping ?? [] {
            if let sourceID = row.sourceID, let note = row.note, !note.isEmpty {
                noteBySourceID[sourceID] = note
            }
        }
        
        for group in plan.groups {
            let resolvedSyntax = self.normalizedSyntaxName(group.syntax)
            let formattedContent = AIDocumentTextCleaner.clean(group.mergedContent)
                .trimmingCharacters(in: .newlines) + "\n"
            
            let matchingEntries = group.sourceIDs.compactMap { entryByID[$0] }.filter { !consumedIDs.contains($0.id) }
            
            // Prefer an existing untitled document or primary entry to host the merged document.
            let primaryEntry = matchingEntries.first(where: { $0.fileURL == nil }) ?? matchingEntries.first
            var finalTitle = group.newTitle
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if finalTitle.isEmpty {
                finalTitle = self.fallbackContentTitle(
                    from: formattedContent,
                    currentTitle: primaryEntry?.originalTitle ?? "整理合并文档"
                )
            }
            
            if let primary = primaryEntry, let doc = primary.document {
                consumedIDs.insert(primary.id)
                updatedCount += 1
                
                // Replace document text safely even when the target tab/pane is not currently focused.
                if let tv = primary.pane?.textView(for: primary.tab ?? PaneTab(document: doc)),
                   tv.shouldChangeText(in: doc.textStorage.range, replacementString: formattedContent)
                {
                    doc.textStorage.replaceCharacters(in: doc.textStorage.range, with: formattedContent)
                    tv.didChangeText()
                } else {
                    doc.textStorage.replaceCharacters(in: doc.textStorage.range, with: formattedContent)
                }
                doc.setSyntax(name: resolvedSyntax)
                
                if let renamed = try? self.renameDocument(doc, to: finalTitle) {
                    if renamed != primary.originalTitle {
                        renamedCount += 1
                    }
                    finalTitle = renamed
                } else {
                    doc.syncToLocalDatabase(force: true)
                }
                primary.pane?.updateTabState()
                primary.windowVC?.view.window?.windowController?.synchronizeWindowTitleWithDocumentName()
                
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
                
                // Preserve user panes: never close the last tab in a pane (which would collapse a split pane).
                for secondary in matchingEntries where secondary.id != primary.id {
                    consumedIDs.insert(secondary.id)
                    if let secDoc = secondary.document,
                       secDoc.fileURL == nil,
                       let secTab = secondary.tab,
                       let secPane = secondary.pane,
                       secPane.tabs.count > 1,
                       let secWinVC = secondary.windowVC,
                       secWinVC.closeMergedTabSafely(secTab, in: secPane)
                    {
                        mappingRows.append((
                            originalTitle: secondary.originalTitle,
                            location: secondary.locationLabel,
                            action: "已并入并关闭多余标签",
                            newTitle: finalTitle,
                            note: noteBySourceID[secondary.id] ?? "内容已去重并入「\(finalTitle)」"
                        ))
                    } else {
                        if let secDoc = secondary.document, secDoc.fileURL == nil {
                            let derivedTitle = self.fallbackContentTitle(from: secondary.content, currentTitle: secondary.originalTitle)
                            if derivedTitle != secondary.originalTitle,
                               let renamed = try? self.renameDocument(secDoc, to: "\(derivedTitle)（已并入）")
                            {
                                renamedCount += 1
                                secondary.pane?.updateTabState()
                                mappingRows.append((
                                    originalTitle: secondary.originalTitle,
                                    location: secondary.locationLabel,
                                    action: "已并入（分屏原位保留）",
                                    newTitle: renamed,
                                    note: noteBySourceID[secondary.id] ?? "内容已并入「\(finalTitle)」，为保持分屏 Pane 不关闭该标签"
                                ))
                                createdGroups.append((title: finalTitle, syntax: resolvedSyntax, summary: group.summary ?? ""))
                                continue
                            }
                        }
                        mappingRows.append((
                            originalTitle: secondary.originalTitle,
                            location: secondary.locationLabel,
                            action: "已并入（原位置保留）",
                            newTitle: finalTitle,
                            note: noteBySourceID[secondary.id] ?? "内容已并入「\(finalTitle)」，原文件/Pane 布局完整保留"
                        ))
                    }
                }
            } else if let opened = try? (NSDocumentController.shared as? DocumentController)?
                .openUntitledDocument(content: formattedContent, title: finalTitle, display: false)
            {
                opened.isExplicitlyNamed = true
                opened.setSyntax(name: resolvedSyntax)
                opened.syncToLocalDatabase(force: true)
                updatedCount += 1
                renamedCount += 1
                if let hostDocVC = (NSApp.mainWindow?.windowController as? DocumentWindowController)?.documentViewController {
                    hostDocVC.openOrFocusDocument(opened, splitRight: false)
                } else {
                    opened.makeWindowControllers()
                    opened.showWindows()
                }
                createdGroups.append((title: finalTitle, syntax: resolvedSyntax, summary: group.summary ?? ""))
                continue
            }
            
            createdGroups.append((title: finalTitle, syntax: resolvedSyntax, summary: group.summary ?? ""))
        }
        
        // Any open untitled document omitted by AI still receives a meaningful content-based filename.
        var untouched = entries.filter { !consumedIDs.contains($0.id) }
        for idx in untouched.indices {
            let entry = untouched[idx]
            guard let doc = entry.document, doc.fileURL == nil else { continue }
            let candidate = self.fallbackContentTitle(from: entry.content, currentTitle: entry.originalTitle)
            if candidate != entry.originalTitle,
               let renamed = try? self.renameDocument(doc, to: candidate)
            {
                renamedCount += 1
                entry.pane?.updateTabState()
                mappingRows.append((
                    originalTitle: entry.originalTitle,
                    location: entry.locationLabel,
                    action: "按内容自动重命名",
                    newTitle: renamed,
                    note: "依据正文首行内容生成清晰文件名"
                ))
                consumedIDs.insert(entry.id)
            }
        }
        untouched = entries.filter { !consumedIDs.contains($0.id) }
        
        let markdown = self.renderMapMarkdown(
            overview: plan.overview,
            mappingRows: mappingRows,
            groups: createdGroups,
            untouchedEntries: untouched
        )
        return ApplyOutcome(mapMarkdown: markdown, updatedCount: updatedCount, renamedCount: renamedCount)
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
