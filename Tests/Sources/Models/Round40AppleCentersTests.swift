//
//  Round40AppleCentersTests.swift
//
//  Tests
//  https://coteditor.com
//

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CotEditor

@MainActor
struct Round40AppleCentersTests {
    
    @Test func cleanExcerptStripsMarkdownSyntaxAndTruncatesCleanly() {
        let md = """
        # 本周架构进展
        ---
        > 核心指标稳定达标
        ```swift
        let x = 1
        ```
        - [x] 完成三栏布局重构
        1. 去除冗余图标与大面积留白
        """
        let excerpt = DocumentCenterState.cleanExcerpt(from: md, maxLength: 96)
        #expect(!excerpt.contains("#"))
        #expect(!excerpt.contains("---"))
        #expect(!excerpt.contains("```"))
        #expect(!excerpt.contains("- [x]"))
        #expect(excerpt.contains("本周架构进展"))
        #expect(excerpt.contains("核心指标稳定达标"))
        
        let longBody = String(repeating: "苹果风格三栏布局阅读体验验证", count: 12)
        let truncated = DocumentCenterState.cleanExcerpt(from: longBody, maxLength: 32)
        #expect(truncated.count <= 32)
        #expect(truncated.hasSuffix("…"))
        
        #expect(DocumentCenterState.cleanExcerpt(from: "   \n---\n```bash\n   ").isEmpty)
    }
    
    
    @Test func weeklyReportCenterSupportsDenseMultiMonthTimelineInThreeColumnLayout() async throws {
        let db = CotLocalDatabase.shared
        var createdIDs: [String] = []
        defer {
            for id in createdIDs {
                db.deleteWeeklyReport(id: id)
            }
        }
        
        let cal = Calendar.current
        let now = Date()
        for idx in 0..<24 {
            let monthOffset = -(idx / 4)
            let targetDate = cal.date(byAdding: .month, value: monthOffset, to: now) ?? now
            let year = cal.component(.year, from: targetDate)
            let month = cal.component(.month, from: targetDate)
            let ym = String(format: "%04d%02d", year, month)
            let day = min(28, 1 + (idx % 4) * 7)
            let endDay = min(28, day + 6)
            let period = String(format: "%@%02d-%02d%02d", ym, day, month, endDay)
            let id = "__test_r40_weekly_\(idx)"
            createdIDs.append(id)
            
            let marker = idx == 9 ? "UNIQUE_APPLE_WEEKLY_MARKER" : "常规研发推进记录 \(idx)"
            db.saveWeeklyReport(
                id: id,
                periodLabel: period,
                yearMonth: ym,
                title: "第\(24 - idx)周 迭代周报",
                content: "# 第\(24 - idx)周 总结\n- \(marker)\n完成核心模块评审与交付。",
                sourcePath: nil,
                isEnhanced: false,
                createdAt: targetDate.addingTimeInterval(Double(-idx * 3600)),
                reloadAfter: idx == 23
            )
        }
        
        let state = WeeklyReportCenterState()
        state.rebuildGroups()
        
        #expect(state.allRowItems.count >= 24)
        #expect(state.groups.count >= 5)
        #expect(state.displayedRows.count >= 24)
        #expect(state.selectedReportID != nil)
        
        let sampleGroup = try #require(state.groups.dropFirst(2).first)
        state.selectedMonth = sampleGroup.month
        #expect(!state.displayedRows.isEmpty)
        #expect(state.displayedRows.allSatisfy { $0.yearMonth == sampleGroup.month })
        
        state.selectedMonth = nil
        state.timeHorizon = .recent3Months
        let recentCount = state.displayedRows.count
        #expect(recentCount >= 8)
        #expect(recentCount <= state.allRowItems.count)
        
        state.timeHorizon = .all
        #expect(await state.applySearch("UNIQUE_APPLE_WEEKLY_MARKER"))
        #expect(state.searchHits.contains { $0.id == "__test_r40_weekly_9" })
        #expect(state.selectedReportID == "__test_r40_weekly_9")
        
        state.searchText = ""
        let view = WeeklyReportCenterView(
            state: state,
            onOpenReport: { _ in },
            onDismiss: { }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1120, height: 720))
        
        let contentView = try #require(window.contentView)
        contentView.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        contentView.layoutSubtreeIfNeeded()
        
        #expect(abs(contentView.bounds.width - 1120) <= 2)
        #expect(abs(contentView.bounds.height - 720) <= 2)
    }
    
    
    @Test func documentCenterSupportsDenseCorpusGroupsTimeFilterAndReaderLayout() async throws {
        let db = CotLocalDatabase.shared
        let testGroups = ["__test_r40_方案", "__test_r40_复盘", "__test_r40_随笔"]
        var docIDs: [String] = []
        defer {
            for id in docIDs {
                db.permanentlyDeleteDocument(id: id, filePath: nil)
            }
            for group in testGroups {
                db.deleteDocumentGroup(named: group)
            }
        }
        
        for group in testGroups {
            _ = db.createDocumentGroup(named: group)
        }
        
        for idx in 0..<30 {
            let id = "doc:__test_r40_doc_\(idx)"
            docIDs.append(id)
            let group = idx.isMultiple(of: 5) ? "" : testGroups[idx % testGroups.count]
            let extra = idx == 14 ? "\n\n关键结论：R40_APPLE_DOC_SEARCH_TOKEN。" : ""
            db.saveDocument(
                id: id,
                title: "结构化文档样本 \(idx)",
                filePath: nil,
                syntax: "Markdown",
                content: "# 样本标题 \(idx)\n- 正在验证苹果三栏文档阅读体验。\(extra)",
                groupName: group
            )
        }
        
        let state = DocumentCenterState()
        state.refresh()
        
        #expect(state.items.count >= 30)
        #expect(state.selectedID != nil)
        
        let targetGroup = testGroups[1]
        state.sidebarFilter = .group(targetGroup)
        #expect(!state.displayedItems.isEmpty)
        #expect(state.displayedItems.allSatisfy { $0.groupName == targetGroup })
        
        state.sidebarFilter = .ungrouped
        #expect(!state.displayedItems.isEmpty)
        #expect(state.displayedItems.allSatisfy { $0.groupName.isEmpty })
        
        state.sidebarFilter = .all
        state.timeHorizon = .today
        #expect(state.displayedItems.count >= 30)
        state.timeHorizon = .older
        #expect(!state.displayedItems.contains { $0.id == "doc:__test_r40_doc_14" })
        
        state.timeHorizon = .all
        #expect(await state.applySearch("R40_APPLE_DOC_SEARCH_TOKEN"))
        let expectedCanonical = DocumentCenterState.canonicalKey(filePath: nil, rawID: "doc:__test_r40_doc_14")
        #expect(state.searchHits.contains { $0.id == expectedCanonical })
        #expect(state.selectedID == expectedCanonical)
        
        state.searchText = ""
        let view = DocumentCenterView(
            state: state,
            onOpenDocument: { _, _ in },
            onCreateNewDocument: { },
            onDismiss: { }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1120, height: 720))
        
        let contentView = try #require(window.contentView)
        contentView.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        contentView.layoutSubtreeIfNeeded()
        
        #expect(abs(contentView.bounds.width - 1120) <= 2)
        #expect(abs(contentView.bounds.height - 720) <= 2)
    }
    
    
    @Test func centerPreviewTextViewRendersAndHighlightsTerms() throws {
        let preview = CenterPreviewTextView(
            text: "第一段包含 AppleNotes 高亮关键词。\n\n第二段检验排版间距。",
            highlightTerms: ["AppleNotes"]
        )
        let host = NSHostingView(rootView: preview)
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 420)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        #expect(host.bounds.width == 520)
        #expect(host.bounds.height == 420)
    }
}
