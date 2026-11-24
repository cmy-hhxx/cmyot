//
//  Round34BeautifulAgentAndPiTests.swift
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
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round34BeautifulAgentAndPiTests {
    
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "coteditor-round34-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    
    // MARK: 1. Beautiful UI Single-File HTML Bundle & Bridge Payloads
    
    @Test func beautifulAgentHTMLBundleLoadsAndContainsBridge() {
        let html = BeautifulAgentUIBundle.htmlDocument()
        #expect(html.contains("CotAgentBridge"))
        #expect(html.contains("<!doctype html>") || html.contains("<!DOCTYPE html>"))
        #expect(!html.contains("not found in application bundle"))
    }
    
    
    // MARK: 2. Pi Kernel Workspace Sync (Custom Headers + Native cot-tools.ts Extension)
    
    @Test func piKernelSyncWritesCustomHeadersAndCotToolsExtension() throws {
        let tempDir = self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "cot.sqlite3"))
        let piDir = tempDir.appending(path: "PiKernel", directoryHint: .isDirectory)
        let manager = PiKernelManager(customAgentDirectoryURL: piDir, database: db)
        
        let profile = AIProvider.openCodeGo.makeProfile(customName: "OpenCode Go Test", modelOverride: "glm-5.3")
        let summary = try manager.syncWorkspace(
            endpoints: [profile],
            keyLookup: { _ in "test-key-placeholder" }
        )
        #expect(summary.providerCount == 1)
        
        let modelsURL = piDir.appending(path: "models.json")
        let modelsData = try Data(contentsOf: modelsURL)
        let root = try #require(try JSONSerialization.jsonObject(with: modelsData) as? [String: Any])
        let providers = try #require(root["providers"] as? [String: Any])
        let pid = PiKernelManager.providerID(for: profile)
        let providerObj = try #require(providers[pid] as? [String: Any])
        let headers = try #require(providerObj["headers"] as? [String: String])
        #expect(headers["x-opencode-session"] == "coteditor-go-session")
        
        let extURL = piDir.appending(path: "extensions/\(PiCotToolsExtension.filename)")
        #expect(FileManager.default.fileExists(atPath: extURL.path(percentEncoded: false)))
        let extSource = try String(contentsOf: extURL, encoding: .utf8)
        #expect(extSource.contains("lookup_stock_quote"))
        #expect(extSource.contains("editor_action"))
        #expect(extSource.contains("before_agent_start"))
    }
    
    
    // MARK: 3. Pi JSONL Stream State (Thinking + Tool Execution + Text)
    
    @Test func piJSONLStreamStateCapturesThinkingToolsAndText() {
        var state = PiKernelManager.JSONLStreamState()
        _ = state.ingest([
            "type": "message_update",
            "assistantMessageEvent": ["type": "thinking_delta", "contentIndex": 0, "delta": "分析三安光电"],
        ])
        let toolStart = state.ingest([
            "type": "tool_execution_start",
            "toolName": "lookup_stock_quote",
        ])
        #expect(state.activeToolName == "lookup_stock_quote")
        #expect(toolStart.toolHint?.contains("lookup_stock_quote") == true)
        
        _ = state.ingest([
            "type": "tool_execution_end",
            "toolName": "lookup_stock_quote",
        ])
        #expect(state.activeToolName == nil)
        #expect(state.completedTools == ["lookup_stock_quote"])
        
        let delta = state.ingest([
            "type": "message_update",
            "assistantMessageEvent": ["type": "text_delta", "contentIndex": 0, "delta": "三安光电今日报收 14.20 元。"],
        ])
        _ = state.ingest(["type": "agent_settled"])
        
        #expect(state.streamedThinking == "分析三安光电")
        #expect(delta.partialSnapshot == "三安光电今日报收 14.20 元。")
        #expect(state.resolvedOutput == "三安光电今日报收 14.20 元。")
        #expect(state.isSettled == true)
    }
    
    
    // MARK: 4. Butler Metadata Backward Compatibility & Stock Candidate Extraction
    
    @Test func butlerMetadataRoundTripAndLegacyReceiptsCompatibility() throws {
        // Legacy JSON array format
        let legacyReceipts = [AppliedActionReceipt(id: "r1", symbolName: "chart.xyaxis.line", summary: "三安光电")]
        let legacyJSON = String(data: try JSONEncoder().encode(legacyReceipts), encoding: .utf8)!
        #expect(CotButlerManager.decodeReceipts(from: legacyJSON) == legacyReceipts)
        
        // Rich structured metadata format
        let rich = ButlerMessageMetadata(
            receipts: legacyReceipts,
            thinking: "先查询三安光电行情",
            thinkingDurationMs: 1240,
            steps: [
                BeautifulAgentThinkingStep(id: "s1", label: "查询实时行情", chip: "三安光电", status: "done", durationMs: 420),
            ],
            toolChips: ["查询实时行情"],
            quoteContext: "三安光电 Q3 财报",
            followUps: ["打开看盘 K 线"]
        )
        let richJSON = CotButlerManager.encodeMetadata(rich)
        let decoded = CotButlerManager.decodeMetadata(from: richJSON)
        #expect(decoded == rich)
        #expect(CotButlerManager.decodeReceipts(from: richJSON) == legacyReceipts)
    }
    
    
    @Test func swiftToolFallbackExtractsStockCandidatesFromChinesePrompts() {
        let candidates = CotSwiftToolFallback.extractStockCandidates(from: "帮我看看现在三安光电啥情况")
        #expect(candidates.contains("三安光电"))
        
        let tickerCandidates = CotSwiftToolFallback.extractStockCandidates(from: "帮我查一下 NVDA 和 600703 今天怎么样")
        #expect(tickerCandidates.contains("NVDA"))
        #expect(tickerCandidates.contains("600703"))
    }
    
    
    // MARK: 5. NEWS Synthetic OG Banner Suppression & Duplicate Title Block Deduplication
    
    @Test func newsSuppressesSyntheticOGBannersAndDeduplicatesLeadingTitle() {
        #expect(AIHotNewsService.isSyntheticOGCardURL("https://aihot.news/api/og?id=12345") == true)
        #expect(AIHotNewsService.isSyntheticOGCardURL("https://cdn.aihot.news/og-card/99.png") == true)
        #expect(AIHotNewsService.isSyntheticOGCardURL("https://example.com/og-image/post.png") == true)
        #expect(AIHotNewsService.isSyntheticOGCardURL("https://techcrunch.com/wp-content/uploads/2026/11/nvidia-ceo.jpg") == false)
        #expect(AIHotNewsService.isSyntheticOGCardURL(nil) == false)
        
        let title = "NVIDIA 宣布黄仁勋复任总裁兼 CEO 并重回董事会"
        let blocks: [NewsArticleBlock] = [
            .heading(level: 2, text: "NVIDIA 宣布黄仁勋复任总裁兼 CEO 并重回董事会"),
            .paragraph("NVIDIA 于 11 月 23 日宣布黄仁勋即刻复任总裁、CEO 及董事会成员。"),
            .heading(level: 3, text: "所属事件"),
        ]
        let sanitized = AIHotNewsService.sanitizedArticleBlocks(blocks, title: title)
        #expect(sanitized.count == 1)
        if case .paragraph(let text) = sanitized.first {
            #expect(text.contains("11 月 23 日"))
        } else {
            Issue.record("Expected first sanitized block to be the body paragraph, not the duplicate title heading")
        }
    }
    
    
    // MARK: 6. Dockable Butler Split-Pane Board Kind & Insert-to-Editor Action
    
    @Test func butlerPaneBoardKindAndInsertActionDecodeCleanly() throws {
        let state = PaneBoardIntentAnalyzer.initialState(for: .butler, text: "帮我查一下恒生科技")
        #expect(state.kind == .butler)
        #expect(state.query == "帮我查一下恒生科技")
        
        let data = try JSONEncoder().encode(state)
        let roundTrip = try JSONDecoder().decode(PaneBoardState.self, from: data)
        #expect(roundTrip == state)
        
        let actionJSON = ###"{"type":"insert_to_editor","text":"## 结论\n- 增长稳健","replaceSelection":false}"###
        let action = try JSONDecoder().decode(CotAgentAction.self, from: Data(actionJSON.utf8))
        #expect(action.type == "insert_to_editor")
        #expect(action.text == "## 结论\n- 增长稳健")
        #expect(action.replaceSelection == false)
    }
}
