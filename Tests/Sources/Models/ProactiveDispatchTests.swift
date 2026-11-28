//
//  ProactiveDispatchTests.swift
//
//  Tests
//

import Foundation
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct ProactiveDispatchTests {
    
    private func makeThursdayAfternoon() -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11
        comps.day = 26 // Thursday
        comps.hour = 15
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }
    
    
    @Test func dndWrapAroundAndSameDayIntervals() {
        #expect(ProactiveDispatchPlanner.isWithinDND(hour: 23, start: 23, end: 8) == true)
        #expect(ProactiveDispatchPlanner.isWithinDND(hour: 0, start: 23, end: 8) == true)
        #expect(ProactiveDispatchPlanner.isWithinDND(hour: 7, start: 23, end: 8) == true)
        #expect(ProactiveDispatchPlanner.isWithinDND(hour: 8, start: 23, end: 8) == false)
        #expect(ProactiveDispatchPlanner.isWithinDND(hour: 15, start: 23, end: 8) == false)
        #expect(ProactiveDispatchPlanner.isWithinDND(hour: 22, start: 23, end: 8) == false)
        
        #expect(ProactiveDispatchPlanner.isWithinDND(hour: 13, start: 13, end: 15) == true)
        #expect(ProactiveDispatchPlanner.isWithinDND(hour: 15, start: 13, end: 15) == false)
        #expect(ProactiveDispatchPlanner.isWithinDND(hour: 12, start: 12, end: 12) == false)
    }
    
    
    @Test func levelLimitsAndLedgerRollover() {
        #expect(ProactiveDispatchPlanner.limits(for: .off) == (0, 0))
        #expect(ProactiveDispatchPlanner.limits(for: .restrained) == (1, 4 * 3600))
        #expect(ProactiveDispatchPlanner.limits(for: .active) == (3, 90 * 60))
        
        let day1 = self.makeThursdayAfternoon()
        let day2 = Calendar.current.date(byAdding: .day, value: 1, to: day1)!
        
        var ledger = ProactiveCooldownLedger()
        #expect(ProactiveDispatchPlanner.canSend(botID: "butler", level: .restrained, ledger: ledger, now: day1))
        ledger = ProactiveDispatchPlanner.recordingSend(ledger, botID: "butler", now: day1)
        
        // Same day restrained -> blocked (1/day cap & 4h cooldown)
        #expect(!ProactiveDispatchPlanner.canSend(botID: "butler", level: .restrained, ledger: ledger, now: day1.addingTimeInterval(3600)))
        // Next day after 4h -> allowed via rollover
        #expect(ProactiveDispatchPlanner.canSend(botID: "butler", level: .restrained, ledger: ledger, now: day2))
    }
    
    
    @Test func customBotDefaultsToOffAndDoesNotDispatch() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "CotProactiveCustom-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        
        let db = CotLocalDatabase(customURL: dir.appending(path: "custom.sqlite3"))
        let botStore = AIBotStore(database: db)
        let custom = botStore.createCustomBot(name: "研究猿", personaPrompt: "帮我读论文")
        #expect(custom.proactiveLevel == .off)
        
        let butler = CotButlerManager(database: db)
        let journal = ProactiveDailyJournalService(database: db)
        let service = CotProactiveDispatchService(
            database: db,
            butler: butler,
            botStore: botStore,
            journalService: journal,
            now: { self.makeThursdayAfternoon() }
        )
        let delivered = await service.tick(manual: false, onlyBotID: custom.id)
        #expect(delivered.isEmpty)
    }
    
    
    @Test func weeklyReportSignalDeliversDMWithUnreadAndRespectsCooldownAndToggle() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "CotProactiveDispatch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        
        let db = CotLocalDatabase(customURL: dir.appending(path: "dispatch.sqlite3"))
        db.appendWeeklyReportFragment("完成设置精简与迁移归档模块")
        
        let butler = CotButlerManager(database: db)
        let botStore = AIBotStore(database: db)
        let journal = ProactiveDailyJournalService(database: db)
        var currentNow = self.makeThursdayAfternoon()
        
        let service = CotProactiveDispatchService(
            database: db,
            butler: butler,
            botStore: botStore,
            journalService: journal,
            now: { currentNow }
        )
        
        let firstRun = await service.tick(manual: false, onlyBotID: AIBotID.weeklyReport.rawValue)
        #expect(firstRun == [AIBotID.weeklyReport.rawValue])
        
        let weeklyDM = butler.sessions.first(where: { $0.botID == AIBotID.weeklyReport.rawValue })
        #expect(weeklyDM != nil)
        #expect(weeklyDM?.unreadCount == 1)
        
        // Immediate second tick blocked by cooldown/daily cap
        currentNow = currentNow.addingTimeInterval(600)
        let secondRun = await service.tick(manual: false, onlyBotID: AIBotID.weeklyReport.rawValue)
        #expect(secondRun.isEmpty)
        
        // Global disabled blocks automatic tick, but manual bypasses and sends to Butler
        db.set("false", forKey: CotLocalDatabase.ConfigKey.proactiveMessagingEnabled)
        let disabledRun = await service.tick(manual: false)
        #expect(disabledRun.isEmpty)
        
        let manualRun = await service.tick(manual: true, onlyBotID: AIBotID.butler.rawValue)
        #expect(manualRun == [AIBotID.butler.rawValue])
    }
    
    
    @MainActor
    @Test func autonomousAgentPatrolExecutesConcreteWorkAndDeliversReport() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "CotAutonomousPatrol-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        
        let db = CotLocalDatabase(customURL: dir.appending(path: "autonomous.sqlite3"))
        db.appendWeeklyReportFragment("完成了导出体积压缩与主动智能体架构升级")
        let butler = CotButlerManager(database: db)
        let botStore = AIBotStore(database: db)
        let engine = CotAutonomousAgentEngine(database: db)
        
        let missions = AutonomousMissionPlanner.selectMissions(
            eligibleBotIDs: [AIBotID.butler.rawValue, AIBotID.weeklyReport.rawValue],
            weeklyFragmentCount: 1,
            ungroupedDocCount: 0,
            unextractedTurnCount: 0,
            unreadNewsCount: 0,
            manual: false
        )
        #expect(missions.contains(where: { $0.botID == AIBotID.weeklyReport.rawValue }))
        #expect(missions.contains(where: { $0.botID == AIBotID.butler.rawValue }))
        
        let reports = await engine.runProactivePatrol(
            manual: true,
            onlyBotID: AIBotID.weeklyReport.rawValue,
            botStore: botStore,
            butlerManager: butler
        )
        #expect(reports.count == 1)
        #expect(!reports[0].deliverables.isEmpty)
        #expect(!db.fetchRecentAutonomousTasks(limit: 10).isEmpty)
        
        let weeklyDM = butler.sessions.first(where: { $0.botID == AIBotID.weeklyReport.rawValue })
        #expect(weeklyDM != nil)
        let msgs = db.fetchButlerMessages(sessionID: weeklyDM?.id ?? "")
        let lastMeta = CotButlerManager.decodeMetadata(from: msgs.last?.actionsJSON ?? "")
        #expect(lastMeta.workReport?.deliverables.count == reports[0].deliverables.count)
    }
}
