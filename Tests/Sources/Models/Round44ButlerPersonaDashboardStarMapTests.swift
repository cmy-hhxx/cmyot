//
//  Round44ButlerPersonaDashboardStarMapTests.swift
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

import CoreGraphics
import Foundation
import Testing
@testable import CotEditor

@Suite(.serialized)
struct Round44ButlerPersonaDashboardStarMapTests {
    
    @Test
    func meetingRoomPassDetectionAndPrompts() {
        #expect(MeetingRoomPersona.isPass("[PASS]"))
        #expect(MeetingRoomPersona.isPass("PASS"))
        #expect(MeetingRoomPersona.isPass("  pass  "))
        #expect(MeetingRoomPersona.isPass("[PASS]."))
        #expect(MeetingRoomPersona.isPass(""))
        #expect(!MeetingRoomPersona.isPass("今天刚整理完两篇草稿。"))
        #expect(!MeetingRoomPersona.isPass("[PASS] 这里其实是正常长发言超过十六个字符的内容"))
        
        let mentionedPrompt = MeetingRoomPersona.systemPrompt(
            bot: .persona,
            name: "小观",
            isMentioned: true,
            isButlerSynthesis: false
        )
        #expect(mentionedPrompt.contains("必须回答"))
        #expect(!mentionedPrompt.contains("只回复 [PASS]"))
        
        let optionalPrompt = MeetingRoomPersona.systemPrompt(
            bot: .persona,
            name: "小观",
            isMentioned: false,
            isButlerSynthesis: false
        )
        #expect(optionalPrompt.contains("[PASS]"))
        #expect(optionalPrompt.contains("群聊说话铁律"))
        
        let banterPrompt = MeetingRoomPersona.systemPrompt(
            bot: .ghost,
            name: "续写幽灵",
            isMentioned: false,
            isButlerSynthesis: false,
            isProgressCheck: false
        )
        #expect(banterPrompt.contains("不是让你汇报工作"))
        #expect(!MeetingRoomRouter.isProgressCheckIntent("嗨"))
        #expect(!MeetingRoomRouter.isProgressCheckIntent("有点累了"))
        #expect(MeetingRoomRouter.isProgressCheckIntent("今天进展怎么样"))
        #expect(MeetingRoomRouter.isProgressCheckIntent(""))
    }
    
    
    @Test
    func meetingRoomRouterMatchesCustomBotAliasMention() {
        let plan = MeetingRoomRouter.parsePrompt(
            "@小观 你好",
            availableBots: AIBotID.allCases,
            customBotAliases: [.persona: ["小观"]]
        )
        #expect(plan.mode == .directCallout(targets: [.persona], shouldRefresh: false))
        #expect(plan.mentionedBots == [.persona])
    }
    
    
    @Test
    func butlerDailyReportComposerDigestFormatting() {
        let filled = ButlerDailyReportComposer.compose(
            botReports: [
                (name: "归档整理", text: "刚把两篇未命名草稿分类收好了。"),
                (name: "幽灵续写", text: "下午陪你补齐了一段技术方案。")
            ],
            butlerName: "阿总"
        )
        #expect(!filled.isEmpty)
        #expect(filled.contains("归档整理"))
        #expect(filled.contains("幽灵续写"))
        
        let emptyDigest = ButlerDailyReportComposer.compose(botReports: [], butlerName: "阿总")
        #expect(!emptyDigest.isEmpty)
        #expect(emptyDigest.contains("阿总"))
    }
    
    
    @Test
    func dashboardImageColorExtractorProducesExpectedTonesAndContrast() throws {
        let side = 32
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for idx in 0..<(side * side) {
            let offset = idx * 4
            bytes[offset] = 255
            bytes[offset + 1] = 0
            bytes[offset + 2] = 0
            bytes[offset + 3] = 255
        }
        
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try #require(CGContext(
            data: &bytes,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        let redImage = try #require(ctx.makeImage())
        let extracted = try #require(DashboardImageColorExtractor.extract(from: redImage))
        
        #expect(extracted.average.red > 0.95)
        #expect(extracted.average.green < 0.05)
        #expect(extracted.average.blue < 0.05)
        #expect(extracted.dominant.saturation > 0.8)
        
        let midpoint = DashboardImageColorExtractor.mixRGB((0.0, 0.2, 0.4), (1.0, 0.8, 0.6), t: 0.5)
        #expect(abs(midpoint.0 - 0.5) < 0.001)
        #expect(abs(midpoint.1 - 0.5) < 0.001)
        #expect(abs(midpoint.2 - 0.5) < 0.001)
        
        let white = HeroRegionTone(red: 1, green: 1, blue: 1)
        let black = HeroRegionTone(red: 0, green: 0, blue: 0)
        #expect(abs(DashboardImageColorExtractor.contrastRatio(white, black) - 21.0) < 0.1)
        
        let oceanBlue = HeroRegionTone(red: 0.28, green: 0.54, blue: 0.84)
        let lightCard = (0.98, 0.98, 0.99)
        let harmonized = try #require(
            DashboardImageColorExtractor.harmonizedAccentRGB(from: oceanBlue, against: lightCard, isDark: false)
        )
        let harmonizedTone = HeroRegionTone(red: harmonized.0, green: harmonized.1, blue: harmonized.2)
        let cardTone = HeroRegionTone(red: lightCard.0, green: lightCard.1, blue: lightCard.2)
        #expect(DashboardImageColorExtractor.contrastRatio(harmonizedTone, cardTone) >= 3.4)
        #expect(harmonized.2 > harmonized.1)
        
        let series = DashboardImageColorExtractor.analogousSeriesRGB(from: harmonized, isDark: false)
        #expect(series.count == 4)
    }
    
    
    @Test
    func starMapOrbitalLayoutIsDeterministicAndNonOverlapping() {
        let clusterCounts = [1, 5, 30]
        let leavesPerClusterCounts = [1, 12, 40]
        
        for clusterCount in clusterCounts {
            for leavesPerCluster in leavesPerClusterCounts {
                let clusterIDs = (0..<clusterCount).map { "cluster-\($0)" }
                var leafIDsByCluster: [String: [String]] = [:]
                for cid in clusterIDs {
                    leafIDsByCluster[cid] = (0..<leavesPerCluster).map { "\(cid)-leaf-\($0)" }
                }
                
                let first = StarMapLayoutEngine.computeOrbital(
                    clusterIDs: clusterIDs,
                    collapsedClusterIDs: [],
                    leafIDsByCluster: leafIDsByCluster
                )
                let second = StarMapLayoutEngine.computeOrbital(
                    clusterIDs: clusterIDs,
                    collapsedClusterIDs: [],
                    leafIDsByCluster: leafIDsByCluster
                )
                
                #expect(first == second)
                #expect(first.usesOrbitalLayout)
                #expect(first.clusters.count == clusterCount)
                #expect(first.leaves.count == clusterCount * leavesPerCluster)
                
                var footprints: [CGRect] = [
                    CGRect(
                        x: first.hubPoint.x - StarMapLayoutEngine.hubFootprint.width * 0.5,
                        y: first.hubPoint.y - StarMapLayoutEngine.hubFootprint.height * 0.5,
                        width: StarMapLayoutEngine.hubFootprint.width,
                        height: StarMapLayoutEngine.hubFootprint.height
                    )
                ]
                for cluster in first.clusters {
                    footprints.append(CGRect(
                        x: cluster.worldPoint.x - StarMapLayoutEngine.clusterFootprint.width * 0.5,
                        y: cluster.worldPoint.y - StarMapLayoutEngine.clusterFootprint.height * 0.5,
                        width: StarMapLayoutEngine.clusterFootprint.width,
                        height: StarMapLayoutEngine.clusterFootprint.height
                    ))
                }
                for leaf in first.leaves {
                    footprints.append(CGRect(
                        x: leaf.worldPoint.x - StarMapLayoutEngine.leafFootprint.width * 0.5,
                        y: leaf.worldPoint.y - StarMapLayoutEngine.leafFootprint.height * 0.5,
                        width: StarMapLayoutEngine.leafFootprint.width,
                        height: StarMapLayoutEngine.leafFootprint.height
                    ))
                }
                
                for i in 0..<footprints.count {
                    for j in (i + 1)..<footprints.count {
                        #expect(!footprints[i].intersects(footprints[j]))
                    }
                }
            }
        }
    }
}
