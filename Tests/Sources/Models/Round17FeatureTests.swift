//
//  Round17FeatureTests.swift
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
import LineEnding
import SwiftUI
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round17FeatureTests {
    
    // MARK: 1. Settings Single-Line Layout & Unified Dimensions
    
    @Test func allSettingsPanesKeepUnifiedSingleLineDimensions() {
        
        #expect(SettingsPaneLayout.width == 740)
        #expect(SettingsPaneLayout.height == 540)
        #expect(SettingsPane.allCases.contains(.dashboard))
        
        for pane in SettingsPane.allCases {
            let host = NSHostingController(rootView: AnyView(pane.view))
            host.view.frame = NSRect(x: 0, y: 0, width: SettingsPaneLayout.width, height: SettingsPaneLayout.height)
            host.view.layoutSubtreeIfNeeded()
            
            let size = host.view.fittingSize
            #expect(abs(size.width - SettingsPaneLayout.width) <= 1, "Pane \(pane.rawValue) width overflow: \(size.width)")
            #expect(abs(size.height - SettingsPaneLayout.height) <= 1, "Pane \(pane.rawValue) height mismatch: \(size.height)")
        }
    }
    
    
    // MARK: 2. Simplified Next Token & Accurate Ghost + Tab Rendering
    
    @Test func nextTokenStrategyExcludesManualMode() {
        
        #expect(AINextTokenStrategy.allCases == [.smart, .proactive])
        #expect(AINextTokenStrategy(rawValue: "manual") == nil)
    }
    
    
    @Test func ghostTabBadgeStaysTightlyAttachedAndClearsCleanly() throws {
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let storage = NSTextStorage()
        let scanner = LineEndingScanner(textStorage: storage, lineEnding: .lf)
        let textView = EditorTextView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 240),
            textStorage: storage,
            lineEndingScanner: scanner
        )
        textView.string = "let value = hello world trailing content"
        textView.selectedRange = NSRange(location: 17, length: 0)
        window.contentView = textView
        window.layoutIfNeeded()
        
        let geometry = try #require(textView.exactCaretGeometry(at: 17))
        #expect(geometry.caretRect.height > 0)
        
        // Previously trailingLineAdvance > 120 hid the Tab badge or pushed badgeX far beyond the suffix text.
        let shiftWidth = textView.funEffects.showGhostSuggestion(
            "NextWord",
            at: geometry.caretRect,
            font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            lineHeight: 20,
            baselineOffset: 14,
            trailingLineAdvance: 220,
            animateEntrance: false
        )
        
        #expect(textView.funEffects.lastGhostShowsTabBadge == true)
        let badgeX = try #require(textView.funEffects.lastTabBadgeXInContainer)
        // Tightly attached after "NextWord" (~65-80pt), NOT offset by trailingLineAdvance (220pt)
        #expect(badgeX < 140)
        // Shift width covers ghost text + Tab badge so LayoutManager shifts trailing text without overlap
        #expect(shiftWidth >= textView.funEffects.lastGhostFrame.width)
        
        textView.funEffects.hideGhostSuggestion(animated: false)
        #expect(textView.funEffects.lastGhostFrame == .zero)
        #expect(textView.funEffects.lastGhostShowsTabBadge == false)
        #expect(textView.funEffects.lastTabBadgeXInContainer == nil)
    }
    
    
    // MARK: 3. Analytics Telemetry, Heatmap, Reminders & 6-Hour AI Digest
    
    @Test func analyticsStatsHeatmapRemindersAndDigestLifecycle() throws {
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot_analytics_test_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "analytics.sqlite3"))
        let manager = AnalyticsManager(database: db)
        
        manager.recordTypedCharacters(120)
        manager.flushPendingStats()
        manager.recordGhostCompletionAccepted(charCount: 36, isFromAI: true)
        manager.recordLocalCompletionHit()
        manager.recordFileCreated()
        manager.recordDocumentSaved()
        
        manager.recordAIUsage(feature: "nextToken", model: "gpt-4o-mini", provider: "OpenAI", inputTokens: 80, outputTokens: 20, latencyMs: 180)
        manager.recordAIUsage(feature: "nextToken", model: "gpt-4o-mini", provider: "OpenAI", inputTokens: 90, outputTokens: 30, latencyMs: 160)
        manager.recordAIUsage(feature: "weeklyReport", model: "deepseek-chat", provider: "DeepSeek", inputTokens: 500, outputTokens: 250, latencyMs: 850)
        
        let stats = manager.todayStats
        #expect(stats.typedChars == 120)
        #expect(stats.aiCompletedChars == 36)
        #expect(stats.aiCompletionAccepts == 1)
        #expect(stats.localHits == 1)
        #expect(stats.filesCreated == 1)
        #expect(stats.documentsSaved == 1)
        #expect(stats.aiRequests == 3)
        #expect(stats.inputTokens == 670)
        #expect(stats.outputTokens == 300)
        #expect(stats.totalTokens == 970)
        
        let models = manager.modelDistribution(days: 30)
        #expect(models.count == 2)
        #expect(models.first?.model == "gpt-4o-mini")
        #expect(models.first?.requests == 2)
        
        let features = manager.featureDistribution(days: 30)
        #expect(features.first?.feature == "nextToken")
        
        let cells = manager.heatmapCells(weeks: 16)
        #expect(cells.count == 112)
        #expect(manager.currentWritingStreak >= 1)
        
        // Reminders & tomorrow highlight
        let tomorrowItem = try #require(manager.addReminder(
            title: "发布新版本并通知测试团队",
            notes: "重点跟进",
            dueDate: AnalyticsManager.tomorrowDate(),
            priority: .high
        ))
        _ = manager.addReminder(title: "整理今日会议记录", dueDate: Date(), priority: .normal)
        #expect(manager.tomorrowReminders.count == 1)
        #expect(manager.todayReminders.count == 1)
        
        manager.toggleReminderCompleted(id: tomorrowItem.id)
        #expect(manager.tomorrowReminders.isEmpty)
        #expect(manager.completedReminders.count == 1)
        
        manager.deleteReminder(id: tomorrowItem.id)
        #expect(manager.completedReminders.isEmpty)
        
        // Note TODO detection from today's DB doc
        db.saveDocument(
            id: "doc-todo-1",
            title: "工作笔记.md",
            filePath: nil,
            syntax: "Markdown",
            content: "# 今日记录\n- [ ] 明天早上评审 API 接口设计\n已完成联调"
        )
        let todos = manager.detectedNoteTodos(limit: 4)
        #expect(todos.count == 1)
        #expect(todos.first?.suggestedForTomorrow == true)
        
        // 6-hour AI digest cadence & parser
        let now = Date()
        #expect(manager.shouldAutoRunDigest(now: now, lastDigest: nil, currentFingerprint: "abc", currentCharCount: 15) == false)
        #expect(manager.shouldAutoRunDigest(now: now, lastDigest: nil, currentFingerprint: "abc", currentCharCount: 40) == true)
        
        let recentDigest = try #require(AnalyticsManager.parseDigestResponse(
            """
            ```json
            {"summary":"今天完成了看板架构与幽灵文本修复。","topics":["数据看板","GhostText"],"tomorrow_focus":"完成端到端回归测试"}
            ```
            """,
            dateKey: AnalyticsManager.dateKey(for: now),
            sourceCharCount: 200,
            sourceFingerprint: "fp1",
            modelUsed: "gpt-4o-mini"
        ))
        #expect(recentDigest.topics == ["数据看板", "GhostText"])
        #expect(recentDigest.tomorrowFocus == "完成端到端回归测试")
        
        let fiveHoursLater = now.addingTimeInterval(5 * 3600)
        #expect(manager.shouldAutoRunDigest(now: fiveHoursLater, lastDigest: recentDigest, currentFingerprint: "fp2", currentCharCount: 300) == false)
        let sevenHoursLater = now.addingTimeInterval(7 * 3600)
        #expect(manager.shouldAutoRunDigest(now: sevenHoursLater, lastDigest: recentDigest, currentFingerprint: "fp1", currentCharCount: 200) == false)
        #expect(manager.shouldAutoRunDigest(now: sevenHoursLater, lastDigest: recentDigest, currentFingerprint: "fp2", currentCharCount: 300) == true)
        
        // Yearly heatmap, AI range distribution, and structured summary points
        let currentYear = Calendar.current.component(.year, from: now)
        let yearly = manager.yearlyHeatmap(year: currentYear, referenceDate: now)
        #expect((52...54).contains(yearly.weeks.count))
        #expect(yearly.weeks.allSatisfy { $0.count == 7 })
        let inYearCells = yearly.weeks.flatMap { $0 }.filter { !$0.isOutOfYear }
        let isLeap = (currentYear.isMultiple(of: 4) && !currentYear.isMultiple(of: 100)) || currentYear.isMultiple(of: 400)
        #expect(inYearCells.count == (isLeap ? 366 : 365))
        #expect(yearly.monthLabels.map(\.month) == Array(1...12))
        let weekIndices = yearly.monthLabels.map(\.weekIndex)
        #expect(weekIndices == weekIndices.sorted())
        #expect(yearly.activeDays >= 1)
        #expect(manager.availableHeatmapYears(referenceDate: now).contains(currentYear))
        
        let todayModels = manager.todayModelDistribution(referenceDate: now)
        #expect(todayModels.count == 2)
        let todayFeatures = manager.todayFeatureDistribution(referenceDate: now)
        let featureShareSum = todayFeatures.reduce(0.0) { $0 + $1.share }
        #expect(abs(featureShareSum - 1.0) < 0.001)
        let todayTotals = manager.aiUsageTotals(forTodayOnly: true, referenceDate: now)
        #expect(todayTotals.requests == 3)
        #expect(todayTotals.totalTokens == 970)
        let thirtyDayTotals = manager.aiUsageTotals(forTodayOnly: false, days: 30, referenceDate: now)
        #expect(thirtyDayTotals.requests == 3)
        #expect(thirtyDayTotals.totalTokens == 970)
        
        let bulletPoints = AnalyticsManager.structuredSummaryPoints(
            from: "- 完成看板栅格重构\n- 热力图改为年度矩阵\n3. 清理全部冗余提示\n- 补充单元测试",
            maxPoints: 3
        )
        #expect(bulletPoints == ["完成看板栅格重构", "热力图改为年度矩阵", "清理全部冗余提示"])
        
        let paragraphPoints = AnalyticsManager.structuredSummaryPoints(
            from: "今天重构了数据看板并对齐所有卡片栅格。把热力图扩展为全年矩阵视图。清理了所有不必要的小字提示与二级标题。",
            maxPoints: 4
        )
        #expect(paragraphPoints.count == 3)
    }
    
    
    @Test func analyticsDashboardEmbedsInsideEditorWindow() {
        
        #expect(WorkspaceCenterKind.allCases.contains(.dashboard))
        
        let contentVC = ContentViewController(document: nil)
        contentVC.loadViewIfNeeded()
        #expect(contentVC.activeCenter == nil)
        
        contentVC.showInWindowCenter(.dashboard)
        #expect(contentVC.activeCenter == .dashboard)
        
        contentVC.hideInWindowCenter()
        #expect(contentVC.activeCenter == nil)
    }
    
    
    // MARK: 4. Local Multi-User Profile Isolation & Avatar Processing
    
    @Test func userProfileCreationAvatarProcessingAndIsolation() throws {
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot_users_test_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let manager = UserProfileManager(rootDirectory: tempDir)
        #expect(manager.profiles.count == 1)
        let defaultProfile = manager.activeProfile
        #expect(defaultProfile.id == "default")
        #expect(manager.deleteProfile(id: defaultProfile.id) == false)  // Refuses deleting sole user
        
        // Center-crop rectangular image into crisp square PNG avatar data
        let sampleImage = NSImage(size: NSSize(width: 320, height: 180))
        sampleImage.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 320, height: 180).fill()
        sampleImage.unlockFocus()
        
        let avatarPNG = try #require(UserProfileManager.processedAvatarPNGData(from: sampleImage))
        let decodedAvatar = try #require(NSImage(data: avatarPNG))
        #expect(abs(decodedAvatar.size.width - decodedAvatar.size.height) <= 1)
        #expect(decodedAvatar.size.width <= 256)
        
        manager.updateProfile(id: defaultProfile.id, displayName: "个人工作区", avatarData: .some(avatarPNG))
        #expect(manager.activeProfile.displayName == "个人工作区")
        #expect(manager.avatarImage(for: manager.activeProfile) != nil)
        
        // Create second isolated local user
        let workProfile = manager.createProfile(
            displayName: "测试账号B",
            avatarData: nil,
            avatarColorHex: "#34C759",
            copyCurrentAIEndpoints: false,
            switchImmediately: true
        )
        #expect(manager.profiles.count == 2)
        #expect(manager.activeProfile.id == workProfile.id)
        #expect(workProfile.dbFilename.hasPrefix("users/cot_user_"))
        
        let dbA = CotLocalDatabase(customURL: manager.databaseURL(for: defaultProfile))
        let dbB = CotLocalDatabase(customURL: manager.databaseURL(for: workProfile))
        dbA.saveDocument(id: "only-a", title: "A的文档", filePath: nil, syntax: "Plain Text", content: "Content A")
        dbB.saveDocument(id: "only-b", title: "B的文档", filePath: nil, syntax: "Plain Text", content: "Content B")
        #expect(dbA.documents.contains(where: { $0.id == "only-a" }))
        #expect(!dbA.documents.contains(where: { $0.id == "only-b" }))
        #expect(dbB.documents.contains(where: { $0.id == "only-b" }))
        #expect(!dbB.documents.contains(where: { $0.id == "only-a" }))
        
        // Switching back persists across fresh manager instance reading cot_accounts.sqlite3
        manager.switchToProfile(id: defaultProfile.id)
        let reloaded = UserProfileManager(rootDirectory: tempDir)
        #expect(reloaded.activeProfile.id == defaultProfile.id)
        #expect(reloaded.activeProfile.displayName == "个人工作区")
        #expect(reloaded.activeProfile.avatarData != nil)
        
        #expect(reloaded.deleteProfile(id: workProfile.id) == true)
        #expect(reloaded.profiles.count == 1)
    }
    
    
    // MARK: 5. Historical Analytics Backfill, Heatmap Day Detail & Tab Formatting Protection
    
    @Test func historicalBackfillPopulatesNonZeroHeatmapAndDayDetail() throws {
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot_backfill_test_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "backfill.sqlite3"))
        let calendar = Calendar.current
        let now = Date()
        let pastDate = try #require(calendar.date(byAdding: .day, value: -5, to: calendar.startOfDay(for: now)))
        let pastKey = AnalyticsManager.dateKey(for: pastDate)
        
        db.saveWeeklyReport(
            id: "202611/20261109-1113",
            periodLabel: "20261109-1113",
            yearMonth: "202611",
            title: "测试-周报-20261109-1113",
            content: String(repeating: "完成核心功能开发与测试验证。", count: 40),
            createdAt: pastDate,
            reloadAfter: true
        )
        
        let manager = AnalyticsManager(database: db)
        manager.backfillHistoricalStatsIfNeeded(referenceDate: now, force: true)
        manager.reloadFromDatabase()
        
        let currentYear = calendar.component(.year, from: now)
        let yearly = manager.yearlyHeatmap(year: currentYear, referenceDate: now)
        let coloredCells = yearly.weeks.flatMap { $0 }.filter { !$0.isOutOfYear && !$0.isFuture && $0.level > 0 }
        #expect(!coloredCells.isEmpty)
        for cell in coloredCells {
            #expect(cell.typedChars > 0 || cell.aiCompletedChars > 0 || cell.aiRequests > 0, "Colored cell \(cell.dateKey) should never show 0")
        }
        
        if let sampleCell = coloredCells.first {
            let detail = manager.dayDetail(for: sampleCell)
            #expect(detail.cell.dateKey == sampleCell.dateKey)
        }
        
        let series14 = manager.dailySeries(days: 14, referenceDate: now)
        #expect(series14.count == 14)
        let rhythm = manager.weekdayActivityDistribution(days: 90, referenceDate: now)
        #expect(rhythm.count == 7)
        _ = pastKey
    }
    
    
    @Test func formattingTabContextProtectsIndentationAndAlignmentFromGhostCompletion() {
        
        let emptySel = NSRange(location: 0, length: 0)
        // Start of line & leading indentation
        #expect(EditorTextView.isFormattingTabContext(linePrefix: "", lineSuffix: "", selectedRange: emptySel) == true)
        #expect(EditorTextView.isFormattingTabContext(linePrefix: "    ", lineSuffix: "hello", selectedRange: emptySel) == true)
        #expect(EditorTextView.isFormattingTabContext(linePrefix: "\t\t", lineSuffix: "", selectedRange: emptySel) == true)
        // After tab or consecutive spaces for column alignment
        #expect(EditorTextView.isFormattingTabContext(linePrefix: "项目名称\t", lineSuffix: "", selectedRange: emptySel) == true)
        #expect(EditorTextView.isFormattingTabContext(linePrefix: "项目名称  ", lineSuffix: "", selectedRange: emptySel) == true)
        // Bare list / outline / heading markers
        #expect(EditorTextView.isFormattingTabContext(linePrefix: "  - ", lineSuffix: "", selectedRange: emptySel) == true)
        #expect(EditorTextView.isFormattingTabContext(linePrefix: "\t1. ", lineSuffix: "", selectedRange: emptySel) == true)
        #expect(EditorTextView.isFormattingTabContext(linePrefix: "## ", lineSuffix: "", selectedRange: emptySel) == true)
        // Pushing existing trailing text right after whitespace
        #expect(EditorTextView.isFormattingTabContext(linePrefix: "标题 ", lineSuffix: "内容", selectedRange: emptySel) == true)
        // Non-empty selection always indents
        #expect(EditorTextView.isFormattingTabContext(linePrefix: "hello", lineSuffix: "", selectedRange: NSRange(location: 0, length: 5)) == true)
        
        // Active prose / code typing should still allow Tab to accept ghost completion
        #expect(EditorTextView.isFormattingTabContext(linePrefix: "今天完成了数据看板", lineSuffix: "", selectedRange: emptySel) == false)
        #expect(EditorTextView.isFormattingTabContext(linePrefix: "let value = ", lineSuffix: "", selectedRange: emptySel) == false)
        #expect(EditorTextView.isFormattingTabContext(linePrefix: "\t1. 优化数据看板", lineSuffix: "", selectedRange: emptySel) == false)
    }
    
    
    @Test func customToolbarVectorIconsRenderCrispImages() {
        
        let icons: [NSImage] = [
            WorkspaceCenterIcons.editableIcon(isEditable: true),
            WorkspaceCenterIcons.editableIcon(isEditable: false),
            WorkspaceCenterIcons.quickEmojiIcon(),
            WorkspaceCenterIcons.analyticsDashboardIcon(isActive: false),
            WorkspaceCenterIcons.analyticsDashboardIcon(isActive: true),
            WorkspaceCenterIcons.appearanceModeIcon(isDark: false),
            WorkspaceCenterIcons.appearanceModeIcon(isDark: true),
            WorkspaceCenterIcons.weeklyReportIcon(isActive: false),
            WorkspaceCenterIcons.weeklyReportIcon(isActive: true),
            WorkspaceCenterIcons.documentCenterIcon(isActive: false),
            WorkspaceCenterIcons.documentCenterIcon(isActive: true),
            WorkspaceCenterIcons.terminalIcon(),
            WorkspaceCenterIcons.aiSettingsIcon(),
            WorkspaceCenterIcons.inspectorIcon(),
            WorkspaceCenterIcons.moreIcon(),
        ]
        for icon in icons {
            #expect(icon.size.width == 18)
            #expect(icon.size.height == 18)
        }
        #expect(WorkspaceCenterIcons.analyticsDashboardIcon(isActive: false).isTemplate == true)
        #expect(WorkspaceCenterIcons.analyticsDashboardIcon(isActive: true).isTemplate == false)
    }
}
