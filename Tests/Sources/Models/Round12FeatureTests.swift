//
//  Round12FeatureTests.swift
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
import Defaults
import Foundation
import Testing
@testable import CotEditor

@MainActor
struct Round12FeatureTests {
    
    @Test func databaseWeeklyReportImportAndStyleRef() throws {
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let sourceTree = tempDir.appending(path: "reports/202610", directoryHint: .isDirectory)
        let macosxNoise = tempDir.appending(path: "reports/__MACOSX/202610", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceTree, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: macosxNoise, withIntermediateDirectories: true)
        
        let standardReport = """
        # 陈明扬-周报-20261012-1016

        本周主要干了以下几件事：
        1. 完成评测集清洗，覆盖 120 条财经 case。

        ## 评测框架
        进展：
        1. 跑通端到端回归，平均耗时降到 4.2s。
        """
        let enhancedReport = """
        # 陈明扬-周报-20261012-1016（增强版）

        完整详细版。
        """
        try standardReport.write(to: sourceTree.appending(path: "20261012-1016.md"), atomically: true, encoding: .utf8)
        try enhancedReport.write(to: sourceTree.appending(path: "20261012-1016_enhanced.md"), atomically: true, encoding: .utf8)
        try "ignored".write(to: sourceTree.appending(path: "._20261012-1016.md"), atomically: true, encoding: .utf8)
        try "ignored".write(to: macosxNoise.appending(path: "20261012-1016.md"), atomically: true, encoding: .utf8)
        
        let zipURL = tempDir.appending(path: "weekly.zip")
        let zipProc = Process()
        zipProc.executableURL = URL(filePath: "/usr/bin/zip")
        zipProc.currentDirectoryURL = tempDir.appending(path: "reports")
        zipProc.arguments = ["-rq", zipURL.path, "."]
        try zipProc.run()
        zipProc.waitUntilExit()
        #expect(zipProc.terminationStatus == 0)
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "test.sqlite3"))
        let importedCount = try db.importWeeklyReports(fromZipURL: zipURL)
        #expect(importedCount == 1)
        #expect(db.weeklyReports.count == 1)
        #expect(db.weeklyReports.allSatisfy { $0.yearMonth == "202610" && !$0.isEnhanced })
        
        let refs = db.styleReferenceWeeklyReports(limit: 2)
        #expect(refs.count == 1)
        #expect(refs[0].isEnhanced == false)
        #expect(refs[0].title == "陈明扬-周报-20261012-1016")
        
        let generated = db.saveGeneratedWeeklyReport(content: "# 陈明扬-周报-20261116-1120\n\n本周主要干了以下几件事：\n1. 修好光标漂移。\n")
        #expect(generated.yearMonth == "202611")
        #expect(generated.periodLabel == "20261116-1120")
        #expect(db.weeklyReports.count == 2)
    }
    
    
    @Test func workspaceOrganizerDecodeAndMapRender() throws {
        
        let fencedJSON = """
        好的，整理方案如下：
        ```json
        {
          "overview": "已合并 2 份零散笔记为 1 份工整清单",
          "groups": [
            {
              "newTitle": "CotEditor 优化清单",
              "syntax": "Markdown",
              "summary": "合并两处重复待办并对齐表格",
              "sourceIDs": ["doc_1", "doc_2"],
              "mergedContent": "| 项目 | 状态 |\\n|---|---|\\n| 光标修复 | 完成 |"
            }
          ],
          "mapping": [
            {
              "sourceID": "doc_1",
              "sourceTitle": "随手记A",
              "action": "主合并",
              "targetTitle": "CotEditor 优化清单",
              "note": "吸收 doc_2"
            }
          ]
        }
        ```
        """
        let plan = try WorkspaceOrganizer.decodePlan(from: fencedJSON)
        #expect(plan.groups.count == 1)
        #expect(plan.groups[0].newTitle == "CotEditor 优化清单")
        #expect(plan.groups[0].sourceIDs == ["doc_1", "doc_2"])
        
        let mapMarkdown = WorkspaceOrganizer.renderMapMarkdown(
            overview: plan.overview,
            mappingRows: [
                (originalTitle: "随手记A", location: "窗口 1 · 分栏 1", action: "主合并并重命名", newTitle: "CotEditor 优化清单", note: "去重保留核心条目"),
            ],
            groups: [
                (title: "CotEditor 优化清单", syntax: "Plain Text", summary: "共 12 条待办"),
            ],
            untouchedEntries: []
        )
        #expect(mapMarkdown.hasPrefix("文档整理合并 Map\n\n\t"))
        #expect(!mapMarkdown.contains("# "))
        #expect(mapMarkdown.contains("\n一、合并前后文档映射表\n\n\t"))
        #expect(mapMarkdown.contains("CotEditor 优化清单"))
        #expect(mapMarkdown.contains("随手记A"))
    }
    
    
    @Test func paneDropZoneAndDragPayload() {
        
        let bounds = NSRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(PaneDropZone.from(point: NSPoint(x: 50, y: 400), in: bounds) == .center)
        #expect(PaneDropZone.from(point: NSPoint(x: 950, y: 400), in: bounds) == .center)
        #expect(PaneDropZone.from(point: NSPoint(x: 500, y: 50), in: bounds) == .center)
        #expect(PaneDropZone.from(point: NSPoint(x: 500, y: 750), in: bounds) == .center)
        #expect(PaneDropZone.from(point: NSPoint(x: 500, y: 400), in: bounds) == .center)
        
        let id = UUID()
        #expect(PaneTab.tabID(from: PaneTab.dragPrefix + id.uuidString) == id)
        #expect(PaneTab.tabID(from: id.uuidString) == id)
        #expect(PaneTab.tabID(from: "not-a-uuid") == nil)
    }
    
    
    @Test func inlineImageExtractsWhenStringAccompaniesImage() {
        
        let image = NSImage(size: NSSize(width: 64, height: 48))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 48).fill()
        image.unlockFocus()
        
        guard let tiffData = image.tiffRepresentation else {
            Issue.record("Failed to render synthetic test image")
            return
        }
        
        let pboard = NSPasteboard.withUniqueName()
        defer { pboard.releaseGlobally() }
        
        // Simulate Finder/WeChat/Chrome copying both filename/text string AND raster image data
        pboard.clearContents()
        pboard.declareTypes([.png, .string], owner: nil)
        let rep = NSBitmapImageRep(data: tiffData)
        let pngData = rep?.representation(using: .png, properties: [:])
        #expect(pngData != nil)
        pboard.setData(pngData, forType: .png)
        pboard.setString("screenshot.png", forType: .string)
        
        let extracted = PlainTextInlineImageStore.shared.extractImage(from: pboard)
        #expect(extracted != nil)
        #expect((extracted?.size.width ?? 0) > 0)
    }
    
    
    @Test func weeklyReportWeekLabelFormat() {
        
        // Wednesday 2026-10-14 -> Monday 20261012 to Friday 1016
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 14
        comps.hour = 12
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        #expect(AIService.currentWeekPeriodLabel(referenceDate: date) == "20261012-1016")
    }
    
    
    @Test func databasePreferencesSyncAndDocumentRename() throws {
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot-prefs-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "prefs.sqlite3"))
        db.saveDocument(id: "doc:abc", title: "旧标题", filePath: nil, syntax: "Markdown", content: "测试内容", highlights: [])
        db.renameDocument(oldID: "doc:abc", newID: "doc:abc", newTitle: "重命名标题", newFilePath: nil)
        #expect(db.documents.count == 1)
        #expect(db.documents[0].title == "重命名标题")
        
        let defaults = UserDefaults.standard
        let oldUseCustom = defaults.object(forKey: DefaultKeys.usesCustomCursorColor.rawValue)
        let oldHex = defaults.object(forKey: DefaultKeys.customCursorColorHex.rawValue)
        defer {
            if let oldUseCustom { defaults.set(oldUseCustom, forKey: DefaultKeys.usesCustomCursorColor.rawValue) }
            else { defaults.removeObject(forKey: DefaultKeys.usesCustomCursorColor.rawValue) }
            if let oldHex { defaults.set(oldHex, forKey: DefaultKeys.customCursorColorHex.rawValue) }
            else { defaults.removeObject(forKey: DefaultKeys.customCursorColorHex.rawValue) }
        }
        
        defaults.set(true, forKey: DefaultKeys.usesCustomCursorColor.rawValue)
        defaults.set("#FF375F", forKey: DefaultKeys.customCursorColorHex.rawValue)
        db.syncUserPreferencesToDatabase()
        
        defaults.set(false, forKey: DefaultKeys.usesCustomCursorColor.rawValue)
        defaults.set("#000000", forKey: DefaultKeys.customCursorColorHex.rawValue)
        db.restoreUserPreferencesFromDatabase(overwriteExisting: true)
        
        #expect(defaults.bool(forKey: DefaultKeys.usesCustomCursorColor.rawValue) == true)
        #expect(defaults.string(forKey: DefaultKeys.customCursorColorHex.rawValue) == "#FF375F")
    }
}
