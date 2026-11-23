//
//  Round30FeatureTests.swift
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
struct Round30FeatureTests {
    
    // MARK: 1. KeyBindings Settings Window Zero Bottom Clipping & Zero Titlebar Safe-Area Offset
    
    @Test func keyBindingsPaneInSidebarSettingsWindowNeverClipsBottomControls() throws {
        let controller = SidebarSettingsWindowController()
        let window = try #require(controller.window)
        defer { window.close() }
        
        controller.openItem(.keyBindings)
        let contentView = try #require(window.contentView)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.30))
        contentView.layoutSubtreeIfNeeded()
        
        #expect(abs(contentView.bounds.width - 780) <= 1)
        #expect(abs(contentView.bounds.height - 560) <= 1)
        
        // Every non-scrolled interactive AppKit control (including bottom-right HelpLink NSButton
        // and top search NSTextField) must lie comfortably inside the [0, 560] window bounds.
        func collectControls(in view: NSView) -> [NSView] {
            var found: [NSView] = []
            if view is NSControl, !(view is NSScroller),
               !view.isHidden, view.alphaValue > 0.01,
               view.bounds.width > 4, view.bounds.height > 4
            {
                let isInsideScrollDoc = sequence(first: view.superview, next: { $0?.superview })
                    .contains { $0 is NSClipView }
                if !isInsideScrollDoc {
                    found.append(view)
                }
            }
            for sub in view.subviews {
                found.append(contentsOf: collectControls(in: sub))
            }
            return found
        }
        
        let controls = collectControls(in: contentView)
        #expect(!controls.isEmpty)
        var foundBottomFooterControl = false
        for ctrl in controls {
            let rectInWindow = ctrl.convert(ctrl.bounds, to: nil)
            #expect(rectInWindow.minY >= 8.0, "Control \(type(of: ctrl)) clipped near bottom: \(rectInWindow)")
            #expect(rectInWindow.maxY <= 558.0, "Control \(type(of: ctrl)) clipped near top: \(rectInWindow)")
            if rectInWindow.minX > 700 && rectInWindow.maxY < 60 {
                foundBottomFooterControl = true
            }
        }
        #expect(foundBottomFooterControl, "Expected footer Help button to be laid out unclipped near bottom-right")
    }
    
    
    // MARK: 2. KeyBinding Menu & Command Localization + Bilingual Search
    
    @Test func keyBindingMenuAndCommandLocalizationNormalizesTyposAndSupportsBilingualSearch() {
        let savedLang = AppLanguage.current(in: .standard)
        defer { savedLang.apply(to: .standard) }
        AppLanguage.simplifiedChinese.apply(to: .standard)
        
        #expect(KeyBindingModel.localizedMenuTitle("CoTEditor") == "CotEditor")
        #expect(KeyBindingModel.localizedMenuTitle("Weekly Report") == "周报")
        #expect(KeyBindingModel.localizedMenuTitle("File") == "文件")
        #expect(KeyBindingModel.localizedCommandTitle("About CoTEditor") == "关于 CotEditor")
        #expect(KeyBindingModel.localizedCommandTitle("Settings...") == "设置…")
        #expect(KeyBindingModel.localizedCommandTitle("Quit CoTEditor") == "退出 CotEditor")
        
        let model = KeyBindingModel()
        model.load()
        if !model.tree.isEmpty {
            let zhMatches = model.rows(searchText: "退出", onlyModified: false)
            let enMatches = model.rows(searchText: "quit", onlyModified: false)
            #expect(zhMatches.count == enMatches.count)
        }
    }
}
