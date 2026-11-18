//
//  Round13FeatureTests.swift
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
import Defaults
import Foundation
import StringUtils
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round13FeatureTests {
    
    @Test func habitCompletionPredictionsAndLearning() {
        
        let predictor = UserHabitPredictor(persistenceKey: nil)
        
        // Built-in high-confidence workflow triggers
        let line1 = "这些都搞定了以后"
        #expect(predictor.predictNextPhrase(in: line1, caretLocation: (line1 as NSString).length) == "进行一次commit")
        
        let line2 = "这些都搞定了以后进行一次commit，然后把代码"
        #expect(predictor.predictNextPhrase(in: line2, caretLocation: (line2 as NSString).length) == "推送到远程仓库")
        
        // Partial typing continuation
        let partial = "这些都搞定了以后进行"
        #expect(predictor.predictNextPhrase(in: partial, caretLocation: (partial as NSString).length) == "一次commit")
        
        // Low-confidence / unknown context stays silent rather than emitting noisy guesses
        let unknown = "今天中午去楼下吃了一碗牛肉面"
        #expect(predictor.predictNextPhrase(in: unknown, caretLocation: (unknown as NSString).length) == nil)
        
        // Dynamic habit learning from repeated user phrases
        let repeated = """
        版本发布前检查清单，每次上线先跑一遍单元测试
        版本发布前检查清单，每次上线先跑一遍单元测试
        版本发布前检查清单，每次上线先跑一遍单元测试
        """
        predictor.learn(from: repeated, persist: false)
        let probe = "版本发布前"
        let learnedPrediction = predictor.predictNextPhrase(in: probe, caretLocation: (probe as NSString).length)
        #expect(learnedPrediction != nil)
        #expect((learnedPrediction?.count ?? 99) <= 14)
    }
    
    
    @Test func generatedDocumentNameLengthBounded() {
        
        var seen: [String] = []
        for _ in 0..<60 {
            let name = GeneratedDocumentName.next(avoiding: seen)
            #expect(!name.isEmpty)
            #expect(name.count <= 8)
            seen.append(name)
        }
    }
    
    
    @Test func documentEditorCounterRefreshAndQuickSave() {
        
        let doc = Document()
        doc.textStorage.replaceCharacters(in: doc.textStorage.range, with: "hello\nworld 测试")
        doc.counter.updatesAll = true
        doc.counter.refreshNow()
        
        #expect(doc.counter.result.lines.entire == 2)
        #expect(doc.counter.result.characters.entire == 14)
        #expect((doc.counter.result.words.entire ?? 0) >= 2)
        
        doc.markEditedByUser()
        #expect(doc.hasUncommittedChanges == true)
        
        doc.performQuickSave()
        #expect(doc.hasUncommittedChanges == false)
    }
    
    
    @Test func vimWordMotionsEnglishCJKAndLastWord() {
        
        // English words across multiple lines including trailing whitespace before newline
        let english = "alpha beta gamma  \ndelta" as NSString
        let w1 = VimEngine.forwardWordLocation(in: english, from: 0, big: false)
        #expect(w1 == 6)   // "beta"
        let w2 = VimEngine.forwardWordLocation(in: english, from: w1, big: false)
        #expect(w2 == 11)  // "gamma"
        let w3 = VimEngine.forwardWordLocation(in: english, from: w2, big: false)
        #expect(w3 == 19)  // "delta" on next line, not stuck before newline!
        #expect(VimEngine.backwardWordLocation(in: english, from: w3, big: false) == 11)
        
        // CJK + ASCII mixed line steps word-by-word instead of skipping the entire sentence to EOL
        let cjk = "先提交代码 然后推送" as NSString
        var stops: [Int] = [0]
        var cursor = 0
        for _ in 0..<8 {
            let next = VimEngine.forwardWordLocation(in: cjk, from: cursor, big: false)
            if next <= cursor { break }
            stops.append(next)
            cursor = next
        }
        #expect(stops.count >= 3)
        #expect(stops[1] < cjk.length - 1)
    }
    
    
    @Test func vimOpenLineBelowCreatesSingleLineDirectlyBelow() throws {
        
        VimState.shared.mode = .normal
        defer { VimState.shared.mode = .normal }
        
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.string = "line1\nline2\nline3"
        textView.setSelectedRange(NSRange(location: 2, length: 0))  // inside "line1"
        
        let engine = VimEngine(textView: textView)
        let oEvent = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "o",
            charactersIgnoringModifiers: "o",
            isARepeat: false,
            keyCode: 31
        ))
        
        let handled = engine.handleKeyDown(oEvent)
        #expect(handled == true)
        #expect(VimState.shared.mode == .insert)
        #expect(textView.string == "line1\n\nline2\nline3")
        // Cursor must sit on the newly inserted blank line 2 (index 6), NOT line 3
        #expect(textView.selectedRange().location == 6)
        
        // Also test `O` (open line above line2 when cursor is on line2)
        VimState.shared.mode = .normal
        textView.string = "alpha\nbeta\ngamma"
        textView.setSelectedRange(NSRange(location: 7, length: 0))  // inside "beta"
        let upperO = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "O",
            charactersIgnoringModifiers: "O",
            isARepeat: false,
            keyCode: 31
        ))
        #expect(engine.handleKeyDown(upperO) == true)
        #expect(textView.string == "alpha\n\nbeta\ngamma")
        #expect(textView.selectedRange().location == 6)
    }
    
    
    @Test func databasePurgesEnhancedWeeklyReportsAndNormalizes() throws {
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot-r13-db-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "test.sqlite3"))
        db.saveWeeklyReport(
            id: "202610/20261012-1016",
            periodLabel: "20261012-1016",
            yearMonth: "202610",
            title: "陈明扬-周报-20261012-1016",
            content: "# 陈明扬-周报-20261012-1016\n\n正文",
            isEnhanced: false
        )
        db.saveWeeklyReport(
            id: "202610/20261012-1016_enhanced",
            periodLabel: "20261012-1016_enhanced",
            yearMonth: "202610",
            title: "陈明扬-周报-20261012-1016（增强版）",
            content: "增强版内容",
            isEnhanced: true
        )
        
        db.purgeEnhancedAndNormalizeWeeklyReports()
        #expect(db.weeklyReports.count == 1)
        #expect(db.weeklyReports[0].isEnhanced == false)
        #expect(!db.weeklyReports[0].title.contains("增强版"))
    }
    
    
    @Test func splitEditorHorizontallyAndVerticallyDivideEvenly() async throws {
        
        let previousSplitVertical = UserDefaults.standard[.splitViewVertical]
        defer { UserDefaults.standard[.splitViewVertical] = previousSplitVertical }
        
        UserDefaults.standard[.splitViewVertical] = false
        let doc = Document()
        doc.textStorage.replaceCharacters(in: doc.textStorage.range, with: String(repeating: "line\n", count: 80))
        let wc = DocumentWindowController(document: doc)
        wc.window?.setFrame(NSRect(x: 0, y: 67, width: 1920, height: 983), display: true)
        wc.showWindow(nil)
        wc.window?.setFrame(NSRect(x: 0, y: 67, width: 1920, height: 983), display: true)
        wc.window?.layoutIfNeeded()
        defer { wc.close() }
        
        let docVC = try #require(wc.documentViewController)
        try await Task.sleep(for: .milliseconds(150))
        
        // Add 9 more tabs so the navigation bar is visible with 10 tabs, matching real usage
        for tabIndex in 0..<9 {
            let extra = Document()
            extra.displayName = "文档\(tabIndex)"
            docVC.openOrFocusDocument(extra, splitRight: false)
        }
        try await Task.sleep(for: .milliseconds(150))
        
        // 1. Horizontal split (⌃A ")
        let initialTextView = try #require(docVC.focusedTextView)
        docVC.splitEditorHorizontally(initialTextView)
        try await Task.sleep(for: .milliseconds(550))
        docVC.view.layoutSubtreeIfNeeded()
        
        let panes2 = docVC.editorViewControllers
        #expect(panes2.count == 2)
        let insets = docVC.view.safeAreaInsets
        let visibleH0 = panes2[0].view.frame.height - max(0, insets.top)
        let visibleH1 = panes2[1].view.frame.height - max(0, insets.bottom)
        #expect(abs(visibleH0 - visibleH1) <= 4, "Horizontal 2-pane split uneven: visibleH0=\(visibleH0), visibleH1=\(visibleH1), frames=\(panes2.map(\.view.frame))")
        
        // 2. Third horizontal pane (⌃A " again)
        let secondTextView = try #require(docVC.focusedTextView)
        docVC.splitEditorHorizontally(secondTextView)
        try await Task.sleep(for: .milliseconds(550))
        docVC.view.layoutSubtreeIfNeeded()
        
        let panes3 = docVC.editorViewControllers
        #expect(panes3.count == 3)
        let thirdTop = panes3[0].view.frame.height - max(0, insets.top)
        let thirdMid = panes3[1].view.frame.height
        let thirdBottom = panes3[2].view.frame.height - max(0, insets.bottom)
        #expect(abs(thirdTop - thirdMid) <= 4 && abs(thirdMid - thirdBottom) <= 4, "Horizontal 3-pane split uneven: visible=(\(thirdTop), \(thirdMid), \(thirdBottom))")
        
        // 3. Vertical split (⌃A %)
        let docV = Document()
        let wcV = DocumentWindowController(document: docV)
        wcV.window?.setFrame(NSRect(x: 0, y: 67, width: 1920, height: 983), display: true)
        wcV.showWindow(nil)
        wcV.window?.setFrame(NSRect(x: 0, y: 67, width: 1920, height: 983), display: true)
        defer { wcV.close() }
        
        let docVCV = try #require(wcV.documentViewController)
        try await Task.sleep(for: .milliseconds(150))
        docVCV.splitEditorVertically(try #require(docVCV.focusedTextView))
        try await Task.sleep(for: .milliseconds(550))
        docVCV.view.layoutSubtreeIfNeeded()
        
        let panesV = docVCV.editorViewControllers
        #expect(panesV.count == 2)
        let width0 = panesV[0].view.frame.width
        let width1 = panesV[1].view.frame.width
        #expect(abs(width0 - width1) <= 4, "Vertical 2-pane split uneven: w0=\(width0), w1=\(width1)")
    }
    
    
    @Test func documentGroupsCreateRenameAssignAndPreserve() throws {
        
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "cot_doc_groups_\(UUID().uuidString).sqlite3")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let db = CotLocalDatabase(customURL: tempURL)
        let createdGroup = db.createDocumentGroup(named: "工作需求")
        #expect(createdGroup == "工作需求")
        #expect(db.documentGroups.contains("工作需求"))
        
        db.saveDocument(id: "doc:a", title: "需求A", filePath: nil, syntax: "Markdown", content: "hello", groupName: "工作需求")
        #expect(db.documents.first(where: { $0.id == "doc:a" })?.groupName == "工作需求")
        
        // Re-saving without specifying groupName preserves the assigned group
        db.saveDocument(id: "doc:a", title: "需求A", filePath: nil, syntax: "Markdown", content: "hello updated")
        #expect(db.documents.first(where: { $0.id == "doc:a" })?.groupName == "工作需求")
        
        // Renaming group migrates documents cleanly
        let renamed = db.renameDocumentGroup(from: "工作需求", to: "核心项目")
        #expect(renamed)
        #expect(db.documentGroups.contains("核心项目"))
        #expect(!db.documentGroups.contains("工作需求"))
        #expect(db.documents.first(where: { $0.id == "doc:a" })?.groupName == "核心项目")
        
        // Dissolving group keeps the document intact as ungrouped
        db.deleteDocumentGroup(named: "核心项目")
        #expect(!db.documentGroups.contains("核心项目"))
        #expect(db.documents.first(where: { $0.id == "doc:a" })?.groupName == "")
    }
    
    
    @Test func weeklyReportCreationUsesStrictFormatAndPeriod() throws {
        
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "cot_weekly_create_\(UUID().uuidString).sqlite3")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let db = CotLocalDatabase(customURL: tempURL)
        db.weeklyReportAuthor = "陈明扬"
        
        let first = db.createWeeklyReport(weekOffset: 0, includeSavedFragments: false)
        #expect(!first.alreadyExisted)
        let currentInfo = CotLocalDatabase.weekPeriodInfo(weekOffset: 0)
        #expect(first.report.periodLabel == currentInfo.periodLabel)
        #expect(first.report.yearMonth == currentInfo.yearMonth)
        #expect(first.report.content.contains("# 陈明扬-周报-\(currentInfo.periodLabel)"))
        #expect(first.report.content.contains("本周主要干了以下几件事："))
        #expect(first.report.content.contains("进展："))
        #expect(first.report.content.contains("## 下周计划"))
        
        // Calling create again for the current week returns the existing entry instead of overwriting
        let second = db.createWeeklyReport(weekOffset: 0, includeSavedFragments: false)
        #expect(second.alreadyExisted)
        #expect(second.report.id == first.report.id)
        
        // Creating last week creates a distinct period entry
        let lastWeek = db.createWeeklyReport(weekOffset: -1, includeSavedFragments: false)
        #expect(!lastWeek.alreadyExisted)
        #expect(lastWeek.report.periodLabel != first.report.periodLabel)
    }
}
