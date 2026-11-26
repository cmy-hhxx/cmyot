//
//  FlowPresentationBlueprint.swift
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

nonisolated enum FlowLayoutKind: String, Codable, CaseIterable, Sendable {
    case pipeline
    case architecture
    case comparison
    case topology
    
    var displayName: String {
        switch self {
            case .pipeline: "主链路"
            case .architecture: "分层架构"
            case .comparison: "对比视图"
            case .topology: "拓扑关系"
        }
    }
}


nonisolated enum FlowPresentationTheme: String, CaseIterable, Codable, Sendable {
    case keynoteLight
    case studioDark
    case editorialPaper
    
    var displayName: String {
        switch self {
            case .keynoteLight: "纯净白板"
            case .studioDark: "深邃画布"
            case .editorialPaper: "暖纸简报"
        }
    }
}


nonisolated struct FlowStepNode: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var indexLabel: String
    var title: String
    var badge: String
    var summary: String
    var linkedArtifactIDs: [String]
    var accentTone: String // "blue" | "teal" | "amber" | "violet" | "slate"
}


nonisolated struct FlowArtifactRef: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var label: String
    var path: String
    var role: String
    var linkedStepIDs: [String]
}


nonisolated struct FlowBranchGroup: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String
    var tag: String
    var path: String
    var summary: String
    var relationLabel: String
}


nonisolated struct FlowPresentationBlueprint: Codable, Equatable, Sendable {
    var title: String
    var layout: FlowLayoutKind
    var steps: [FlowStepNode]
    var artifacts: [FlowArtifactRef]
    var branches: [FlowBranchGroup]
    var coreTakeaway: String?
}


/// Pure deterministic parser transforming arbitrary structured/semi-structured workflow prose
/// into an interactive `FlowPresentationBlueprint` (and validating LLM JSON blueprints).
nonisolated enum FlowPresentationParser {
    
    private static let stepPrefixRegex = try! NSRegularExpression(
        pattern: #"^(?:step\s*([0-9]+)|([0-9]+))\s*[:：\.、\)\]]\s*(.+)$"#,
        options: [.caseInsensitive]
    )
    private static let pathTokenRegex = try! NSRegularExpression(
        pattern: #"(?:~|/(?:[A-Za-z0-9_.\-]+/)*[A-Za-z0-9_.\-]+|s3://[^\s]+|https?://[^\s]+)"#,
        options: []
    )
    private static let parenNoteRegex = try! NSRegularExpression(
        pattern: #"[（\(]([^）\)]+)[）\)]"#,
        options: []
    )
    private static let englishTokenRegex = try! NSRegularExpression(
        pattern: #"[A-Za-z][A-Za-z0-9_]{2,}"#,
        options: []
    )
    private static let tones = ["blue", "teal", "violet", "amber", "slate"]
    
    
    static func parseOffline(from rawText: String) -> FlowPresentationBlueprint {
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !lines.isEmpty else {
            return FlowPresentationBlueprint(
                title: "流程概览",
                layout: .pipeline,
                steps: [],
                artifacts: [],
                branches: [],
                coreTakeaway: nil
            )
        }
        
        var title = "流程概览"
        var inArtifactSection = false
        var steps: [FlowStepNode] = []
        var artifacts: [FlowArtifactRef] = []
        var branches: [FlowBranchGroup] = []
        var coreTakeaway: String? = nil
        
        for (idx, line) in lines.enumerated() {
            let cleanLine = line.trimmingCharacters(in: CharacterSet(charactersIn: "-•* \t"))
            if cleanLine.isEmpty { continue }
            
            if idx == 0 && !Self.isStepLine(cleanLine) && !Self.containsPath(cleanLine) {
                title = cleanLine.trimmingCharacters(in: CharacterSet(charactersIn: ":："))
                continue
            }
            
            if cleanLine.contains("重要") || cleanLine.contains("路径") || cleanLine.contains("目录") {
                if !Self.containsPath(cleanLine) && cleanLine.hasSuffix("：") || cleanLine.hasSuffix(":") {
                    inArtifactSection = true
                    continue
                }
            }
            
            if cleanLine.hasPrefix("本质上") || cleanLine.hasPrefix("核心") || cleanLine.hasPrefix("总结") {
                let cleaned = cleanLine
                    .replacingOccurrences(of: "本质上来说；", with: "")
                    .replacingOccurrences(of: "本质上来说：", with: "")
                    .replacingOccurrences(of: "本质上：", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                coreTakeaway = cleaned
                continue
            }
            
            if cleanLine.hasPrefix("注意") || cleanLine.lowercased().contains("ab_test") || cleanLine.lowercased().contains("ab 测试") {
                if let path = Self.firstPath(in: cleanLine) {
                    let rest = cleanLine
                        .replacingOccurrences(of: "注意：", with: "")
                        .replacingOccurrences(of: "注意:", with: "")
                        .replacingOccurrences(of: path, with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: " ：:;；"))
                    let branchTitle = cleanLine.lowercased().contains("ab") ? "AB 测试分支" : "平行分支"
                    let relation = rest.contains("一致") ? "与主链路一致" : "独立分支"
                    branches.append(FlowBranchGroup(
                        id: "br_\(branches.count + 1)",
                        title: branchTitle,
                        tag: "PARALLEL",
                        path: path,
                        summary: rest.isEmpty ? branchTitle : rest,
                        relationLabel: relation
                    ))
                    continue
                }
            }
            
            if let path = Self.firstPath(in: cleanLine), (inArtifactSection || !Self.isStepLine(cleanLine)) {
                let roleText = Self.stripLeadingNumber(
                    cleanLine.replacingOccurrences(of: path, with: "")
                ).trimmingCharacters(in: CharacterSet(charactersIn: " ：:;；-"))
                let label = URL(filePath: path).lastPathComponent
                artifacts.append(FlowArtifactRef(
                    id: "art_\(artifacts.count + 1)",
                    label: label.isEmpty ? path : label,
                    path: path,
                    role: roleText.isEmpty ? label : roleText,
                    linkedStepIDs: []
                ))
                continue
            }
            
            if let parsedStep = Self.parseStep(line: cleanLine, fallbackIndex: steps.count + 1) {
                steps.append(parsedStep)
            } else if cleanLine.contains("→") || cleanLine.contains("->") {
                let sep = cleanLine.contains("→") ? "→" : "->"
                for seg in cleanLine.components(separatedBy: sep) {
                    let t = seg.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { continue }
                    let n = steps.count + 1
                    steps.append(FlowStepNode(
                        id: "step_\(n)",
                        indexLabel: String(format: "%02d", n),
                        title: String(t.prefix(28)),
                        badge: "",
                        summary: t,
                        linkedArtifactIDs: [],
                        accentTone: Self.tones[(n - 1) % Self.tones.count]
                    ))
                }
            }
        }
        
        // Cross-link steps <-> artifacts deterministically
        Self.crossLink(&steps, &artifacts)
        
        return FlowPresentationBlueprint(
            title: title,
            layout: steps.isEmpty && !artifacts.isEmpty ? .topology : .pipeline,
            steps: steps,
            artifacts: artifacts,
            branches: branches,
            coreTakeaway: coreTakeaway
        )
    }
    
    
    static func parseJSON(from llmOutput: String) -> FlowPresentationBlueprint? {
        guard let start = llmOutput.firstIndex(of: "{"),
              let end = llmOutput.lastIndex(of: "}")
        else { return nil }
        let jsonStr = String(llmOutput[start...end])
        guard let data = jsonStr.data(using: .utf8),
              var decoded = try? JSONDecoder().decode(FlowPresentationBlueprint.self, from: data)
        else { return nil }
        guard !decoded.steps.isEmpty || !decoded.artifacts.isEmpty else { return nil }
        Self.crossLink(&decoded.steps, &decoded.artifacts)
        return decoded
    }
    
    
    // MARK: - Helpers
    
    private static func isStepLine(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return Self.stepPrefixRegex.firstMatch(in: line, options: [], range: range) != nil
    }
    
    
    private static func parseStep(line: String, fallbackIndex: Int) -> FlowStepNode? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = Self.stepPrefixRegex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges > 3,
              let bodyRange = Range(match.range(at: 3), in: line)
        else { return nil }
        
        var num = fallbackIndex
        if let r1 = Range(match.range(at: 1), in: line), let parsed = Int(line[r1]) {
            num = parsed
        } else if let r2 = Range(match.range(at: 2), in: line), let parsed = Int(line[r2]) {
            num = parsed
        }
        
        let body = String(line[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let note = Self.extractParenNote(in: body)
        let mainPart = Self.stripParenNote(in: body)
        let shortTitle = Self.compactStepTitle(mainPart)
        let badge = Self.firstEnglishToken(in: body) ?? ""
        
        return FlowStepNode(
            id: "step_\(num)",
            indexLabel: String(format: "%02d", num),
            title: shortTitle,
            badge: badge,
            summary: note.isEmpty ? mainPart : "\(mainPart) · \(note)",
            linkedArtifactIDs: [],
            accentTone: Self.tones[(max(1, num) - 1) % Self.tones.count]
        )
    }
    
    
    private static func crossLink(_ steps: inout [FlowStepNode], _ artifacts: inout [FlowArtifactRef]) {
        for aIdx in artifacts.indices {
            let art = artifacts[aIdx]
            let artLower = "\(art.path) \(art.label) \(art.role)".lowercased()
            let artTokens = Self.matchingKeywords(in: artLower)
            
            for sIdx in steps.indices {
                let step = steps[sIdx]
                let stepLower = "\(step.title) \(step.badge) \(step.summary)".lowercased()
                let stepTokens = Self.matchingKeywords(in: stepLower)
                
                let tokenOverlap = !Set(artTokens).intersection(stepTokens).isEmpty
                let directPathMatch = stepLower.contains(art.label.lowercased())
                    || (artLower.contains("eval_input") && (stepLower.contains("评测输入") || stepLower.contains("eval_input") || stepLower.contains("eval input")))
                    || (artLower.contains("eval_output") && !artLower.contains("cluster") && (stepLower.contains("评测输出") || stepLower.contains("eval_output")))
                    || (artLower.contains("cluster") && (stepLower.contains("聚类") || stepLower.contains("cluster")))
                
                if tokenOverlap || directPathMatch {
                    if !steps[sIdx].linkedArtifactIDs.contains(art.id) {
                        steps[sIdx].linkedArtifactIDs.append(art.id)
                    }
                    if !artifacts[aIdx].linkedStepIDs.contains(step.id) {
                        artifacts[aIdx].linkedStepIDs.append(step.id)
                    }
                }
            }
        }
    }
    
    
    private static func matchingKeywords(in lower: String) -> [String] {
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        let matches = Self.englishTokenRegex.matches(in: lower, options: [], range: range)
        return matches.compactMap { m in
            Range(m.range, in: lower).map { String(lower[$0]) }
        }.filter { $0.count >= 4 && $0 != "aime" && $0 != "daily" && $0 != "step" }
    }
    
    
    private static func containsPath(_ text: String) -> Bool {
        Self.firstPath(in: text) != nil
    }
    
    
    private static func firstPath(in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = Self.pathTokenRegex.firstMatch(in: text, options: [], range: range),
              let r = Range(match.range, in: text)
        else { return nil }
        return String(text[r])
    }
    
    
    private static func firstEnglishToken(in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = Self.englishTokenRegex.firstMatch(in: text, options: [], range: range),
              let r = Range(match.range, in: text)
        else { return nil }
        return String(text[r])
    }
    
    
    private static func extractParenNote(in text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = Self.parenNoteRegex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text)
        else { return "" }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    private static func stripParenNote(in text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Self.parenNoteRegex
            .stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    private static func stripLeadingNumber(_ text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = Self.stepPrefixRegex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 3,
              let r = Range(match.range(at: 3), in: text)
        else { return text }
        return String(text[r])
    }
    
    
    private static func compactStepTitle(_ raw: String) -> String {
        let clean = raw
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count <= 24 { return clean }
        if let firstPart = clean.components(separatedBy: " 到 ").first, firstPart.count >= 3, firstPart.count <= 20 {
            return firstPart.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(clean.prefix(24))
    }
}
