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
}
