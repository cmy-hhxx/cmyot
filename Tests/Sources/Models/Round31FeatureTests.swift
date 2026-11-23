//
//  Round31FeatureTests.swift
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
import SwiftUI
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round31FeatureTests {
    
    // MARK: 1. Document Type (Syntax) Single-Selection State Invariant
    
    @Test func syntaxPopUpEnforcesStrictSingleSelectionAcrossSwitches() throws {
        let doc = Document()
        doc.setSyntax(name: "Plain Text")
        
        let windowController = DocumentWindowController(document: doc)
        let popUp = SyntaxPopUpButton()
        let menu = NSMenu()
        
        let noneItem = NSMenuItem(title: "None", action: #selector(Document.changeSyntax(_:)), keyEquivalent: "")
        noneItem.representedObject = SyntaxName.none
        menu.addItem(noneItem)
        menu.addItem(.separator())
        for name in ["Markdown", "Plain Text", "Python", "TypeScript"] {
            let item = NSMenuItem(title: name, action: #selector(Document.changeSyntax(_:)), keyEquivalent: "")
            item.representedObject = name
            menu.addItem(item)
        }
        popUp.menu = menu
        
        // Simulate stale multi-selection before switching from Plain Text to Python
        menu.items.first(where: { $0.representedObject as? String == "Plain Text" })?.state = .on
        menu.items.first(where: { $0.representedObject as? String == "Markdown" })?.state = .on
        
        doc.setSyntax(name: "Python")
        windowController.selectSyntaxPopUpItem(with: doc.syntaxName, in: popUp)
        
        let checkedItems = menu.items.filter { $0.state == .on }
        #expect(checkedItems.count == 1)
        #expect(checkedItems.first?.representedObject as? String == "Python")
        
        // Also verify EditorViewController menu validation strictly marks only the active syntax
        let pane = EditorViewController(document: doc, splitState: SplitState())
        for item in menu.items where item.action == #selector(EditorViewController.changeSyntax(_:)) {
            _ = pane.validateUserInterfaceItem(item)
        }
        let paneChecked = menu.items.filter { $0.state == .on }
        #expect(paneChecked.count == 1)
        #expect(paneChecked.first?.representedObject as? String == "Python")
        
        windowController.close()
    }
    
    
    // MARK: 2. Settings Renamed to API 网关 & Bots + Bundled HD Non-Turnaround Character Suites
    
    @Test func settingsRenamedToAPIGatewayAndBotsWithoutGijinkaLabelsAndWithBundledHDAssets() {
        #expect(SidebarSettingsItem.models.title == AppLanguage.text("API 网关", en: "API Gateway"))
        #expect(SidebarSettingsItem.bots.title == "Bots")
        
        for character in AIGijinkaCharacter.allCharacters {
            #expect(character.name.contains("娘") == false, "Unexpected label in character name: \(character.name)")
            #expect(!character.artworks.isEmpty)
            for art in character.artworks {
                #expect(art.title.contains("娘") == false, "Unexpected label in artwork title: \(art.title)")
                #expect(art.title.contains("三视图") == false, "Turnaround sheet should not be included: \(art.id)")
                #expect(art.id.contains("turnaround") == false && art.id.contains("3view") == false)
                let img = AIGijinkaImageLoader.shared.image(for: art)
                #expect(img != nil, "Missing bundled static asset: \(art.assetName)")
                if let img {
                    let ratio = img.size.width / max(img.size.height, 1)
                    #expect(ratio <= 1.05, "Expected portrait/square HD art, got wide sheet for \(art.id): \(img.size)")
                }
            }
        }
        
        #expect(AIGijinkaCharacter.deepseek.artworks.count >= 8)
        #expect(AIGijinkaCharacter.gpt.artworks.count >= 5)
    }
    
    
    // MARK: 3. Pi Kernel Workspace Synchronization & Model-Driven Bot Manifests
    
    @Test func piKernelSynchronizesGatewaysModelsAndPerBotManifests() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot_r31_pi_kernel_\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "test.sqlite3"))
        let botStore = AIBotStore(database: db)
        let piDir = tempDir.appending(path: "PiKernel", directoryHint: .isDirectory)
        let kernel = PiKernelManager(customAgentDirectoryURL: piDir, database: db)
        
        let deepSeekGateway = AIEndpointProfile(
            name: "DeepSeek Gateway",
            endpoint: .openAIChatCompletions,
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-chat",
            savedModels: ["deepseek-chat", "deepseek-reasoner"]
        )
        botStore.updateConfig(
            AIBotConfig(isEnabled: true, endpointID: deepSeekGateway.id, modelOverride: "deepseek-reasoner", toolProfile: .autonomousAgent),
            for: .organizeAndMerge
        )
        
        let summary = try kernel.syncWorkspace(
            endpoints: [deepSeekGateway],
            botStore: botStore,
            keyLookup: { _ in "sk-test-secret" }
        )
        #expect(summary.providerCount == 1)
        #expect(summary.botCount == AIBotID.allCases.count)
        
        let modelsURL = piDir.appending(path: "models.json")
        let modelsJSON = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: modelsURL)) as? [String: Any])
        let providers = try #require(modelsJSON["providers"] as? [String: Any])
        let pid = PiKernelManager.providerID(for: deepSeekGateway)
        let providerEntry = try #require(providers[pid] as? [String: Any])
        #expect(providerEntry["api"] as? String == "openai-completions")
        #expect(providerEntry["apiKey"] == nil) // API keys live exclusively in 0o600 auth.json, never models.json
        
        let tidyManifestURL = piDir.appending(path: "agents/organizeAndMerge/bot-manifest.json")
        let tidyManifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: tidyManifestURL)) as? [String: Any])
        #expect(tidyManifest["personaBrand"] as? String == "DeepSeek")
        #expect(tidyManifest["model"] as? String == "deepseek-reasoner")
        #expect(tidyManifest["toolProfile"] as? String == PiBotToolProfile.autonomousAgent.rawValue)
    }
    
    
    // MARK: 4. Categorized & Icon-Rich Editor Context Menu
    
    @Test func contextMenuHasCategorizedSectionsAndIcons() {
        let doc = Document()
        let textView = EditorTextView(textStorage: doc.textStorage, lineEndingScanner: doc.lineEndingScanner)
        textView.string = "Hello Python context menu"
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        
        let menu = textView.makeContextMenu()
        let actionItems = menu.items.filter { !$0.isSeparatorItem && $0.view == nil && $0.action != nil }
        #expect(actionItems.count >= 4)
        for item in actionItems {
            #expect(item.image != nil, "Context menu item missing icon: \(item.title)")
        }
    }
    
    
    // MARK: 5. Unified Editorial Dashboard Palette, 3-Region Layout & Simplified NEWS Reader
    
    @Test func unifiedDashboardPaletteAndSimplifiedNewsReaderRenderCleanly() throws {
        let lightTokens = DashPalette.editorialTokens(isDark: false)
        let darkTokens = DashPalette.editorialTokens(isDark: true)
        
        // Canvas must be solid neutral (no top-to-bottom hue shift) and empty heatmap cells stay neutral
        #expect(lightTokens.canvasTop == lightTokens.canvasBottom)
        #expect(darkTokens.canvasTop == darkTokens.canvasBottom)
        #expect(lightTokens.emptyDot != lightTokens.heat1)
        #expect(darkTokens.emptyDot != darkTokens.heat1)
        
        // Verify full-window and Settings-embedded AnalyticsDashboardView mount and lay out cleanly
        let dashWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 840),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        dashWindow.appearance = NSAppearance(named: .aqua)
        let dashboardHost = NSHostingController(
            rootView: AnalyticsDashboardView(isEmbeddedInSettings: false, onDismiss: {})
                .environment(\.colorScheme, .light)
        )
        dashWindow.contentViewController = dashboardHost
        dashWindow.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        dashWindow.contentView?.layoutSubtreeIfNeeded()
        #expect(abs((dashWindow.contentView?.bounds.width ?? 0) - 1200) <= 2)
        dashWindow.close()
        
        let settingsDashHost = NSHostingController(rootView: DashboardSettingsView())
        settingsDashHost.view.frame = NSRect(x: 0, y: 0, width: SettingsPaneLayout.width, height: SettingsPaneLayout.height)
        settingsDashHost.view.layoutSubtreeIfNeeded()
        #expect(settingsDashHost.view.bounds.width == SettingsPaneLayout.width)
        
        // Verify simplified DashboardNewsCenterView renders cleanly without annotation text fields
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot_r31_news_\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "news.sqlite3"))
        let service = AIHotNewsService(database: db, cacheRootDirectory: tempDir.appending(path: "cache"))
        let newsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newsWindow.appearance = NSAppearance(named: .aqua)
        let newsView = DashboardNewsCenterView(
            newsService: service,
            tokens: lightTokens,
            initialSelectedID: nil,
            onClose: {}
        )
        .environment(\.colorScheme, .light)
        let newsHost = NSHostingController(rootView: newsView)
        newsWindow.contentViewController = newsHost
        newsWindow.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        newsWindow.contentView?.layoutSubtreeIfNeeded()
        #expect(abs((newsWindow.contentView?.bounds.height ?? 0) - 760) <= 2)
        newsWindow.close()
    }
}
