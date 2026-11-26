//
//  FlowPresentationTests.swift
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

import Foundation
import Testing
@testable import CotEditor

@Suite
struct FlowPresentationTests {
    
    private static let aimeSample = """
    AIME 评测数据梳理：
        step1:  清洗评测输入 到 eval_input 下面（准备 eval input 的jsonl）
        step2:  进行评测 (输出评测输出到 eval_output下面）
        step3:  进行聚类 (输出 cluster tree 到 cluster 目录下面）
        step4:  对 评测输入 和 评测输出 回补 task 和 subtask 标签 （通过接口查）
        
        重要数据路径： 
            1. /mnt/aime_eval_ssd/1_aime/eval_input/0_daily_eval_input 评测最权威的输入路径
            2. /mnt/aime_eval_ssd/1_aime/eval_output/0_daily_eval 与之对应的评测最权威的评测输出路径
            3. /mnt/aime_eval_ssd/1_aime/eval_output/cluster 针对评测输出的问题聚类树路径
        
        本质上来说； 就这三个目录覆盖了整个评测链路，其余都是中间产物
        
        注意： /mnt/aime_eval_ssd/1_aime/ab_test 是 AB 测试的目录； 这里面有一套内部的逻辑（和正常的评测一致）
    """
    
    
    @Test func offlineParserHandlesAIMEWorkflow() {
        let bp = FlowPresentationParser.parseOffline(from: Self.aimeSample)
        
        #expect(bp.title == "AIME 评测数据梳理")
        #expect(bp.layout == .pipeline)
        #expect(bp.steps.count == 4)
        #expect(bp.artifacts.count == 3)
        #expect(bp.branches.count == 1)
        #expect(bp.coreTakeaway?.contains("三个目录") == true)
        
        // Verify authoritative path mapping
        let inputArt = bp.artifacts.first { $0.path.contains("0_daily_eval_input") }
        let outputArt = bp.artifacts.first { $0.path.hasSuffix("0_daily_eval") }
        let clusterArt = bp.artifacts.first { $0.path.hasSuffix("cluster") }
        
        #expect(inputArt?.linkedStepIDs.contains("step_1") == true)
        #expect(inputArt?.linkedStepIDs.contains("step_4") == true)
        #expect(outputArt?.linkedStepIDs.contains("step_2") == true)
        #expect(outputArt?.linkedStepIDs.contains("step_4") == true)
        #expect(clusterArt?.linkedStepIDs.contains("step_3") == true)
        
        // Verify AB test branch extracted separately
        #expect(bp.branches.first?.path == "/mnt/aime_eval_ssd/1_aime/ab_test")
    }
    
    
    @Test func jsonParserDecodesAndLinks() throws {
        let json = """
        ```json
        {
          "title": "评测链路",
          "layout": "pipeline",
          "steps": [
            {"id":"step_1","indexLabel":"01","title":"清洗输入","badge":"eval_input","summary":"准备 jsonl","linkedArtifactIDs":[],"accentTone":"blue"}
          ],
          "artifacts": [
            {"id":"art_1","label":"0_daily_eval_input","path":"/mnt/eval_input/0_daily_eval_input","role":"权威输入","linkedStepIDs":[]}
          ],
          "branches": [],
          "coreTakeaway": "单目录覆盖输入"
        }
        ```
        """
        let bp = try #require(FlowPresentationParser.parseJSON(from: json))
        #expect(bp.steps.first?.linkedArtifactIDs.contains("art_1") == true)
        #expect(bp.artifacts.first?.linkedStepIDs.contains("step_1") == true)
    }
    
    
    @Test func htmlRendererProducesCleanZeroExplainerCanvases() {
        let bp = FlowPresentationParser.parseOffline(from: Self.aimeSample)
        let bannedPhrases = ["点击即可", "提示：", "说明：", "你可以", "Click to ", "Tip:"]
        
        for theme in FlowPresentationTheme.allCases {
            let html = FlowPresentationRenderer.renderHTML(blueprint: bp, initialTheme: theme)
            #expect(html.contains("data-theme=\"\(theme.rawValue)\""))
            #expect(html.contains("AIME 评测数据梳理"))
            #expect(html.contains("/mnt/aime_eval_ssd/1_aime/eval_input/0_daily_eval_input"))
            for phrase in bannedPhrases {
                #expect(!html.contains(phrase))
            }
        }
    }
}
