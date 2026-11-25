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
    static func renameDocument(
        _ document: Document,
        to rawNewName: String,
        syncDatabase: Bool = true,
        reloadAfter: Bool = true
    ) throws -> String {
        
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
                newFilePath: newPath,
                reloadAfter: reloadAfter
            )
            // Migrate any pre-save untitled DB record into this file-backed row so no stale duplicate lingers.
            if CotLocalDatabase.shared.documents.contains(where: { $0.id == rawDocID }) {
                CotLocalDatabase.shared.renameDocument(
                    oldID: rawDocID,
                    oldFilePath: nil,
                    newID: newPath,
                    newTitle: targetURL.lastPathComponent,
                    newFilePath: newPath,
                    reloadAfter: reloadAfter
                )
            }
            if syncDatabase {
                document.syncToLocalDatabase(force: true)
            }
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
                newFilePath: nil,
                reloadAfter: reloadAfter
            )
            if syncDatabase {
                document.syncToLocalDatabase(force: true)
            }
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
        
        guard AIService.shared.isConfigured(for: .organizeAndMerge) else {
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
            let profile = AIBotStore.shared.resolvedEndpointProfile(for: .organizeAndMerge) ?? AIEndpointStore.activeProfile
            let resolvedModel = AIBotStore.shared.resolvedConfiguration(for: .organizeAndMerge).model
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let profile {
                let model = resolvedModel.isEmpty ? profile.model.trimmingCharacters(in: .whitespacesAndNewlines) : resolvedModel
                return model.isEmpty ? profile.displayName : "\(profile.displayName) · \(model)"
            }
            return resolvedModel.isEmpty ? "AI" : resolvedModel
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
        
        // Step 1: Snapshot every document into local SQLite before any modification, then run Data Funnel.
        progressController.state.markStepActive(
            0,
            detail: "正在备份 \(entries.count) 份文档快照并启动数据漏斗…",
            progress: 0.12,
            headline: "步骤 1/4：备份快照与漏斗初筛"
        )
        CotLocalDatabase.shared.withTransaction {
            for entry in entries {
                guard let doc = entry.document else { continue }
                doc.syncToLocalDatabase(force: true)
            }
        }
        
        let funnelInputs: [OrganizeFunnelInput] = entries.map { entry in
            OrganizeFunnelInput(
                id: entry.id,
                dbRecordID: entry.fileURL?.path(percentEncoded: false)
                    ?? (entry.document.map { $0.databaseDocumentID.hasPrefix("doc:") ? $0.databaseDocumentID : "doc:\($0.databaseDocumentID)" } ?? entry.id),
                title: entry.originalTitle,
                filePath: entry.fileURL?.path(percentEncoded: false),
                syntax: entry.syntaxName,
                currentGroup: "",
                content: entry.content,
                updatedAt: entry.document?.lastManualSaveDate ?? Date(),
                isOpenNow: true,
                isUntitled: DocumentCenterAgentOrganizer.isGenericUntitled(entry.originalTitle, hasFilePath: entry.fileURL != nil)
            )
        }
        let localFunnel = DocumentOrganizeFunnel.runLocalFunnel(items: funnelInputs)
        let preFunnelResult = self.applyLocalWorkspaceFunnel(localFunnel, entries: entries)
        let survivingEntries = preFunnelResult.survivingEntries
        
        let funnelSummaryParts: [String] = [
            preFunnelResult.deletedCount > 0 ? "清理无效/乱码 \(preFunnelResult.deletedCount) 份" : nil,
            preFunnelResult.mergedDuplicateCount > 0 ? "合并重复 \(preFunnelResult.mergedDuplicateCount) 份" : nil,
            "保留 \(survivingEntries.count) 份进入 AI 整理",
        ].compactMap(\.self)
        progressController.state.markStepCompleted(0, detail: funnelSummaryParts.joined(separator: " · "))
        
        guard !survivingEntries.isEmpty else {
            let mapMarkdown = self.renderMapMarkdown(
                overview: "数据漏斗已完成清洗：\(funnelSummaryParts.joined(separator: "，"))。",
                mappingRows: preFunnelResult.mappingRows,
                groups: [],
                untouchedEntries: []
            )
            self.finishOrganizeAndOpenMap(
                mapMarkdown: mapMarkdown,
                targetWindow: targetWindow,
                progressController: progressController,
                summary: "漏斗整理完成：\(funnelSummaryParts.joined(separator: " · "))。"
            )
            return
        }
        
        let shards = DocumentOrganizeFunnel.makeShards(survivingEntries, shardSize: 8)
        let totalBatches = shards.count
        
        progressController.state.markStepActive(
            1,
            detail: "正在分 \(totalBatches) 批并发整理 \(survivingEntries.count) 份核心文档…",
            progress: 0.25,
            headline: "步骤 2/4：分片并发 AI 归类与提炼"
        )
        
        let organizeTask = Task { @MainActor in
            do {
                let mergedPlan = try await self.runShardedMergePlan(
                    shards: shards,
                    progressController: progressController
                )
                
                guard !Task.isCancelled else { return }
                progressController.state.markStepCompleted(
                    1,
                    detail: "AI 分片分析完成（共 \(totalBatches) 批 · \(mergedPlan.groups.count) 组）"
                )
                
                progressController.state.markStepActive(
                    2,
                    detail: "正在按文档内容重命名并排版（保持原有分屏 Pane 不变）…",
                    progress: 0.78,
                    headline: "步骤 3/4：原位更新文档与智能重命名"
                )
                
                let outcome = self.apply(
                    plan: mergedPlan,
                    entries: survivingEntries,
                    prefixedMappingRows: preFunnelResult.mappingRows
                )
                
                progressController.state.markStepCompleted(
                    2,
                    detail: "已清理 \(preFunnelResult.deletedCount) 份无效 · 合并 \(preFunnelResult.mergedDuplicateCount) 份重复 · 更新 \(outcome.updatedCount) 组"
                )
                
                progressController.state.markStepActive(
                    3,
                    detail: "正在生成《整理合并 Map》总览文档…",
                    progress: 0.92,
                    headline: "步骤 4/4：生成整理合并 Map"
                )
                
                self.finishOrganizeAndOpenMap(
                    mapMarkdown: outcome.mapMarkdown,
                    targetWindow: targetWindow,
                    progressController: progressController,
                    summary: "整理完成：清理 \(preFunnelResult.deletedCount) 份无效、合并 \(preFunnelResult.mergedDuplicateCount) 份重复、整理 \(outcome.updatedCount) 组、重命名 \(outcome.renamedCount) 份。"
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
    
    
    private static let mapTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
    
    
    /// Builds a structured Map document from a parsed merge plan.
    static func renderMapMarkdown(
        overview: String?,
        mappingRows: [(originalTitle: String, location: String, action: String, newTitle: String, note: String)],
        groups: [(title: String, syntax: String, summary: String)],
        untouchedEntries: [SourceEntry]
    ) -> String {
        
        let timestamp = Self.mapTimestampFormatter.string(from: Date())
        
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
        
        return AIDocumentTextCleaner.cleanOrganized(lines.joined(separator: "\n")) + "\n"
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
    
    
    private static func apply(
        plan: MergePlan,
        entries: [SourceEntry],
        prefixedMappingRows: [(originalTitle: String, location: String, action: String, newTitle: String, note: String)] = []
    ) -> ApplyOutcome {
        
        let entryByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        var consumedIDs = Set<String>()
        var mappingRows: [(originalTitle: String, location: String, action: String, newTitle: String, note: String)] = prefixedMappingRows
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
            let formattedContent = AIDocumentTextCleaner.cleanOrganized(group.mergedContent)
                .trimmingCharacters(in: .newlines) + "\n"
            
            let matchingEntries = group.sourceIDs.compactMap { entryByID[$0] }.filter { !consumedIDs.contains($0.id) }
            
            // Prefer an existing untitled document or primary entry to host the merged document.
            let primaryEntry = matchingEntries.first(where: { $0.fileURL == nil }) ?? matchingEntries.first
            var finalTitle = group.newTitle
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if primaryEntry?.fileURL == nil {
                finalTitle = Self.strippingMarkdownExtension(from: finalTitle)
            }
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
                
                if let renamed = try? self.renameDocument(doc, to: finalTitle, syncDatabase: false, reloadAfter: false) {
                    if renamed != primary.originalTitle {
                        renamedCount += 1
                    }
                    finalTitle = renamed
                }
                // Always keep AI-organized summaries as Plain Text rather than Markdown.
                doc.setSyntax(name: resolvedSyntax)
                doc.syncToLocalDatabase(force: true)
                CotLocalDatabase.shared.reloadDocuments()
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
        
        // One-click AI organize & merge always keeps output as Plain Text.
        SyntaxName.none
    }
    
    
    private static func strippingMarkdownExtension(from title: String) -> String {
        
        let lower = title.lowercased()
        if lower.hasSuffix(".markdown") {
            return String(title.dropLast(".markdown".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if lower.hasSuffix(".md") {
            return String(title.dropLast(".md".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title
    }
    
    
    private struct WorkspaceFunnelOutcome {
        let survivingEntries: [SourceEntry]
        let mappingRows: [(originalTitle: String, location: String, action: String, newTitle: String, note: String)]
        let deletedCount: Int
        let mergedDuplicateCount: Int
    }
    
    
    private static func applyLocalWorkspaceFunnel(
        _ funnel: OrganizeFunnelStageResult,
        entries: [SourceEntry]
    ) -> WorkspaceFunnelOutcome {
        let entryByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        var mappingRows: [(originalTitle: String, location: String, action: String, newTitle: String, note: String)] = []
        var removedIDs = Set<String>()
        var deletedCount = 0
        var mergedDuplicateCount = 0
        
        CotLocalDatabase.shared.withTransaction {
            for junk in funnel.junkToDelete {
                guard let entry = entryByID[junk.item.id] else { continue }
                // Never delete external files on disk; clean untitled junk tabs & DB records directly.
                if let doc = entry.document, doc.fileURL == nil {
                    removedIDs.insert(entry.id)
                    deletedCount += 1
                    CotLocalDatabase.shared.permanentlyDeleteDocument(id: junk.item.dbRecordID, filePath: nil)
                    if let tab = entry.tab, let pane = entry.pane, pane.tabs.count > 1, let winVC = entry.windowVC {
                        _ = winVC.closeMergedTabSafely(tab, in: pane)
                    } else {
                        doc.textStorage.replaceCharacters(in: doc.textStorage.range, with: "")
                        doc.updateChangeCount(.changeCleared)
                    }
                    mappingRows.append((
                        originalTitle: entry.originalTitle,
                        location: entry.locationLabel,
                        action: "漏斗清理（\(junk.reason.label)）",
                        newTitle: "已删除",
                        note: "自动识别为\(junk.reason.label)并清理"
                    ))
                }
            }
            
            for cluster in funnel.mergeClusters {
                guard let primary = entryByID[cluster.primary.id], let primaryDoc = primary.document else { continue }
                if cluster.mergedContent != primaryDoc.textStorage.string {
                    primaryDoc.textStorage.replaceCharacters(in: primaryDoc.textStorage.range, with: cluster.mergedContent)
                    primaryDoc.syncToLocalDatabase(force: true)
                }
                for dup in cluster.duplicates {
                    guard let sec = entryByID[dup.id] else { continue }
                    removedIDs.insert(sec.id)
                    mergedDuplicateCount += 1
                    if let secDoc = sec.document, secDoc.fileURL == nil {
                        CotLocalDatabase.shared.permanentlyDeleteDocument(id: dup.dbRecordID, filePath: nil)
                        if let tab = sec.tab, let pane = sec.pane, pane.tabs.count > 1, let winVC = sec.windowVC {
                            _ = winVC.closeMergedTabSafely(tab, in: pane)
                        }
                    }
                    mappingRows.append((
                        originalTitle: sec.originalTitle,
                        location: sec.locationLabel,
                        action: "漏斗去重合并",
                        newTitle: primary.originalTitle,
                        note: "\(cluster.reason)，内容已无损并入主文档"
                    ))
                }
            }
        }
        
        if deletedCount > 0 || mergedDuplicateCount > 0 {
            CotLocalDatabase.shared.reloadDocuments()
        }
        
        let mergedContentByID = Dictionary(uniqueKeysWithValues: funnel.mergeClusters.map { ($0.primary.id, $0.mergedContent) })
        let surviving: [SourceEntry] = entries.compactMap { entry in
            guard !removedIDs.contains(entry.id) else { return nil }
            guard let updatedText = mergedContentByID[entry.id] else { return entry }
            return SourceEntry(
                id: entry.id,
                windowIndex: entry.windowIndex,
                paneIndex: entry.paneIndex,
                originalTitle: entry.originalTitle,
                fileURL: entry.fileURL,
                syntaxName: entry.syntaxName,
                content: updatedText,
                windowVC: entry.windowVC,
                pane: entry.pane,
                tab: entry.tab,
                document: entry.document
            )
        }
        
        return WorkspaceFunnelOutcome(
            survivingEntries: surviving,
            mappingRows: mappingRows,
            deletedCount: deletedCount,
            mergedDuplicateCount: mergedDuplicateCount
        )
    }
    
    
    private static func runShardedMergePlan(
        shards: [[SourceEntry]],
        progressController: WorkspaceOrganizeProgressController
    ) async throws -> MergePlan {
        if shards.count == 1, let singleShard = shards.first {
            let prompt = self.buildPrompt(from: singleShard)
            let raw = try await AIService.shared.run(.organizeAndMerge, on: prompt) { partial in
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
            return try self.decodePlan(from: raw)
        }
        
        let totalBatches = shards.count
        var shardPlans: [(Int, MergePlan)] = []
        var completed = 0
        let maxConcurrency = min(3, totalBatches)
        
        try await withThrowingTaskGroup(of: (Int, MergePlan).self) { group in
            var nextIdx = 0
            func enqueue() {
                guard nextIdx < totalBatches, !Task.isCancelled else { return }
                let idx = nextIdx
                let shard = shards[idx]
                nextIdx += 1
                group.addTask { @MainActor in
                    let prompt = self.buildPrompt(from: shard)
                    let raw = try await AIService.shared.run(.organizeAndMerge, on: prompt) { _ in }
                    let plan = try self.decodePlan(from: raw)
                    return (idx, plan)
                }
            }
            for _ in 0..<maxConcurrency { enqueue() }
            while let result = try await group.next() {
                shardPlans.append(result)
                completed += 1
                let prog = 0.25 + (Double(completed) / Double(totalBatches)) * 0.47
                progressController.state.markStepActive(
                    1,
                    detail: "分片整理完成 \(completed)/\(totalBatches) 批…",
                    progress: prog,
                    headline: "步骤 2/4：分片并发 AI 归类与提炼"
                )
                enqueue()
            }
        }
        
        shardPlans.sort { $0.0 < $1.0 }
        let combinedGroups = shardPlans.flatMap { $0.1.groups }
        let combinedMappings = shardPlans.flatMap { $0.1.mapping ?? [] }
        let overviews = shardPlans.compactMap { $0.1.overview?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return MergePlan(
            overview: overviews.isEmpty ? "已分 \(totalBatches) 批完成文档整理与合并。" : overviews.joined(separator: " "),
            groups: combinedGroups,
            mapping: combinedMappings
        )
    }
    
    
    private static func finishOrganizeAndOpenMap(
        mapMarkdown: String,
        targetWindow: NSWindow?,
        progressController: WorkspaceOrganizeProgressController,
        summary: String
    ) {
        if let hostDocVC = (targetWindow?.windowController as? DocumentWindowController)?.documentViewController {
            hostDocVC.openGeneratedTab(
                title: "整理合并 Map",
                content: mapMarkdown,
                syntaxName: SyntaxName.none,
                databaseID: "organize-map:latest"
            )
        } else if let mapDoc = try? (NSDocumentController.shared as? DocumentController)?
            .openUntitledDocument(content: mapMarkdown, title: "整理合并 Map", display: true)
        {
            mapDoc.isExplicitlyNamed = true
            mapDoc.setSyntax(name: SyntaxName.none)
            mapDoc.syncToLocalDatabase(force: true)
        }
        
        var primaryDocVC: DocumentViewController?
        for window in NSApp.orderedWindows {
            guard let docVC = (window.windowController as? DocumentWindowController)?.documentViewController else { continue }
            if primaryDocVC == nil { primaryDocVC = docVC }
            for pane in docVC.editorViewControllers {
                pane.updateTabState()
            }
            window.windowController?.synchronizeWindowTitleWithDocumentName()
        }
        primaryDocVC?.savePaneTabsSessionToDatabase()
        
        progressController.state.markStepCompleted(3, detail: "已生成并在当前焦点 Pane 中打开《整理合并 Map》")
        progressController.state.markCompleted(summary: summary)
    }
}
