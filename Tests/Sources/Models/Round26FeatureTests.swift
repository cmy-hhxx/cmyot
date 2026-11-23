//
//  Round26FeatureTests.swift
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

@MainActor
struct Round26FeatureTests {
    
    // MARK: 1. Inline Image Top-Handle Shrinking Releases Top Space
    
    @Test func inlineImageTopHandleResizeNeverTrapsTopBlankSpace() {
        let start = NSRect(x: 40, y: 100, width: 320, height: 240)
        // Shrinking via top-right corner moves nextFrame.minY downward (from 100 -> 220)
        let shrunk = NSRect(x: 40, y: 220, width: 160, height: 120)
        
        for handle in [BoundingBoxHandle.topLeft, .topCenter, .topRight] {
            let zeroStart = EditorTextView.resolvedOffsetYAfterResize(
                startOffsetY: 0,
                startFrame: start,
                nextFrame: shrunk,
                handle: handle
            )
            #expect(zeroStart == 0)
            
            let existingPadding = EditorTextView.resolvedOffsetYAfterResize(
                startOffsetY: 90,
                startFrame: start,
                nextFrame: shrunk,
                handle: handle
            )
            #expect(existingPadding == 0)
        }
        
        // Shrinking via bottom handle also proportionally releases existing top padding
        let southShrunk = NSRect(x: 40, y: 100, width: 160, height: 120)
        let southReleased = EditorTextView.resolvedOffsetYAfterResize(
            startOffsetY: 100,
            startFrame: start,
            nextFrame: southShrunk,
            handle: .bottomRight
        )
        #expect(southReleased == 50)
        
        // Enlarging upward consumes existing top blank padding first
        let enlarged = NSRect(x: 40, y: 60, width: 373, height: 280)
        let consumed = EditorTextView.resolvedOffsetYAfterResize(
            startOffsetY: 90,
            startFrame: start,
            nextFrame: enlarged,
            handle: .topCenter
        )
        #expect(consumed == 50)
    }
    
    
    // MARK: 2. Stratified Danmaku Scheduler Never Overlaps Pills or Center Avatar
    
    @Test func danmakuLaneSchedulerHasZeroOverlapAcrossTimestamps() {
        let tags = (0..<8).map { index in
            UserPersonalityTag(
                id: "tag-\(index)",
                label: "深夜灵感写作者\(index)",
                explanation: "测试",
                tone: .calm
            )
        }
        let avatarRect = CGRect(x: -34, y: -34, width: 68, height: 68)
        let pillW = AvatarDanmakuLaneScheduler.pillEstimatedWidth
        let pillH = AvatarDanmakuLaneScheduler.pillEstimatedHeight
        
        for timestamp in [0.0, 1.7, 5.3, 12.8, 27.4] {
            let scheduled = AvatarDanmakuLaneScheduler.schedule(tags: tags, elapsed: timestamp, shockExpand: 0)
            #expect(scheduled.count == 8)
            
            let rects = scheduled.map { item in
                CGRect(
                    x: item.x - pillW * 0.5,
                    y: item.y - pillH * 0.5,
                    width: pillW,
                    height: pillH
                )
            }
            
            for (idx, rect) in rects.enumerated() {
                #expect(!rect.intersects(avatarRect), "Tag \(idx) collided with center avatar at t=\(timestamp)")
                for otherIdx in (idx + 1)..<rects.count {
                    #expect(!rect.intersects(rects[otherIdx]), "Tags \(idx) & \(otherIdx) overlapped at t=\(timestamp)")
                }
            }
        }
    }
    
    
    // MARK: 3. Todos Strictly Sorted in Reverse Chronological DDL Order
    
    @Test func todosSortStrictlyByDeadlineDescending() {
        let now = Date()
        let dayKey = AnalyticsManager.dateKey(for: now)
        let items = [
            UserReminder(id: "earliest", title: "1", dueDate: now.addingTimeInterval(300), dueDayKey: dayKey, createdAt: now, isPinned: true, hasDeadline: true),
            UserReminder(id: "timeless", title: "2", dueDate: now.addingTimeInterval(99_999), dueDayKey: dayKey, createdAt: now.addingTimeInterval(-50), isPinned: true, hasDeadline: false),
            UserReminder(id: "latest", title: "3", dueDate: now.addingTimeInterval(14_400), dueDayKey: dayKey, createdAt: now.addingTimeInterval(-20), isPinned: true, hasDeadline: true),
            UserReminder(id: "middle", title: "4", dueDate: now.addingTimeInterval(3_600), dueDayKey: dayKey, createdAt: now.addingTimeInterval(-10), isPinned: true, hasDeadline: true),
        ]
        
        let sorted = ToolbarCapsuleTodoHelper.prioritizedTodos(items)
        #expect(sorted.map(\.id) == ["latest", "middle", "earliest", "timeless"])
    }
    
    
    // MARK: 4. Mathematical Hermite C¹ & Gaussian μ ± σ Trend Engine
    
    @Test func mathematicalTrendCurveComputesNonNegativeSplineAndBand() {
        let series: [Double] = [0, 420, 1250, 300, 0, 2400, 1800, 950, 0, 1100, 3100, 620, 1400, 2050]
        let result = MathematicalTrendCurveEngine.compute(values: series, samplesPerSegment: 6, bandwidth: 1.65)
        
        #expect(result.samples.count == (series.count - 1) * 6 + 1)
        #expect(result.peakIndex == 10)
        #expect(result.peakValue == 3100)
        #expect(abs(result.averageValue - (series.reduce(0, +) / Double(series.count))) < 0.01)
        
        for sample in result.samples {
            #expect(sample.value >= 0)
            #expect(sample.lower >= 0)
            #expect(sample.mu >= sample.lower)
            #expect(sample.upper >= sample.mu)
        }
    }
    
    
    // MARK: 5. Reference-Faithful Eval Sunburst Layout Engine
    
    @Test func evalSunburstEngineMatchesConcentricRingsAndFoldingRules() {
        let children = (0..<10).map { idx in
            let subA = EvalSunburstLayoutEngine.Node(id: "m\(idx)/a", name: "续写", value: Double((10 - idx) * 60))
            let subB = EvalSunburstLayoutEngine.Node(id: "m\(idx)/b", name: "翻译", value: Double((10 - idx) * 40))
            return EvalSunburstLayoutEngine.Node(
                id: "m\(idx)",
                name: "Model-\(idx)",
                value: Double((10 - idx) * 100),
                outputValue: Double((10 - idx) * 35),
                children: [subA, subB]
            )
        }
        let rawRoot = EvalSunburstLayoutEngine.Node(id: "root", name: "总用量", value: 5500, children: children)
        let root = EvalSunburstLayoutEngine.prepareTree(rawRoot, fold: true)
        
        // KEEP = 7 + 1 folded "其他" node = 8 inner children
        #expect(root.children.count == 8)
        #expect(root.children.last?.isOther == true)
        #expect(root.children.last?.name == "其他")
        
        let openNode = EvalSunburstLayoutEngine.biggestNonOtherChild(of: root)
        #expect(openNode?.id == "m0")
        
        let layout = EvalSunburstLayoutEngine.layout(focus: root, open: openNode)
        let innerArcs = layout.arcs.filter { !$0.isMark && $0.ring == .inner }
        let outerArcs = layout.arcs.filter { !$0.isMark && $0.ring == .outer }
        
        #expect(innerArcs.count == 8)
        #expect(outerArcs.count == 2)
        
        if let openArc = innerArcs.first(where: { $0.node.id == openNode?.id }) {
            #expect(openArc.r0Ratio == EvalSunburstLayoutEngine.innerRatioRange.lowerBound)
            #expect(openArc.r1Ratio == EvalSunburstLayoutEngine.innerRatioRange.upperBound)
            for outArc in outerArcs {
                #expect(outArc.r0Ratio == EvalSunburstLayoutEngine.outerRatioRange.lowerBound)
                #expect(outArc.r1Ratio == EvalSunburstLayoutEngine.outerRatioRange.upperBound)
                #expect(outArc.a0 >= openArc.a0 - 1e-6)
                #expect(outArc.a1 <= openArc.a1 + 1e-6)
            }
        }
    }
}
