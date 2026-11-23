//
//  AIBot.swift
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
import Observation

/// Framing anchor used when displaying a Bot persona artwork inside portrait/square/pack cards.
nonisolated enum AIGijinkaCropAnchor: String, Sendable, Equatable, Hashable {
    case top
    case center
    case leading
}

/// One high-resolution single-character portrait bundled in `Assets.xcassets/BotAvatars` (no 3-view sheets).
nonisolated struct AIGijinkaArtwork: Identifiable, Sendable, Equatable, Hashable {
    
    let id: String
    let title: String
    let assetName: String
    let urlString: String
    let cropAnchor: AIGijinkaCropAnchor
    
    init(
        id: String,
        title: String,
        urlString: String = "",
        assetName: String? = nil,
        cropAnchor: AIGijinkaCropAnchor = .top
    ) {
        self.id = id
        self.title = title
        self.assetName = assetName ?? "BotArt_\(id)"
        self.urlString = urlString
        self.cropAnchor = cropAnchor
    }
    
    var url: URL? {
        URL(string: self.urlString)
    }
}

/// Model-linked HD visual persona suite resolved strictly from the user's selected API Gateway & Model.
nonisolated struct AIGijinkaCharacter: Identifiable, Sendable, Equatable, Hashable {
    
    let id: String
    let name: String
    let brand: String
    let accentHex: String
    let artworks: [AIGijinkaArtwork]
    
    var primaryAssetName: String {
        self.artworks.first?.assetName ?? ""
    }
    
    var portraitURLString: String {
        self.artworks.first?.urlString ?? ""
    }
    
    var portraitURL: URL? {
        self.artworks.first?.url
    }
    
    /// Picks a deterministic HD portrait for `botID` so multiple Bots sharing one model
    /// (for example when using only DeepSeek) automatically display a cohesive, varied suite
    /// unless the user explicitly selected `variantOverride`.
    func artwork(for botID: AIBotID, variantOverride: Int? = nil) -> AIGijinkaArtwork {
        guard !self.artworks.isEmpty else {
            return AIGijinkaArtwork(id: self.id, title: "标准立绘", urlString: "", assetName: "", cropAnchor: .top)
        }
        let count = self.artworks.count
        if let variantOverride {
            let safe = ((variantOverride % count) + count) % count
            return self.artworks[safe]
        }
        let botIndex = AIBotID.allCases.firstIndex(of: botID) ?? 0
        return self.artworks[botIndex % count]
    }
    
    // MARK: Bundled HD Single-Character Portrait Suites (Assets.xcassets/BotAvatars · Zero Turnaround Sheets)
    
    static let deepseek = AIGijinkaCharacter(
        id: "deepseek",
        name: "DeepSeek",
        brand: "DeepSeek",
        accentHex: "#3B82F6",
        artworks: [
            .init(id: "deepseek-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/deepseek.webp?v=20261114"),
            .init(id: "deepseek-v4f", title: "速记形态", urlString: "https://img.aigengtu.com/refs/gj-deepseek-v4flash.webp"),
            .init(id: "deepseek-v4f-vision", title: "视觉巡检", urlString: "https://img.aigengtu.com/refs/gj-deepseek-v4flash-vision.webp"),
            .init(id: "deepseek-harness", title: "Harness 定稿", urlString: "https://img.aigengtu.com/refs/gj-deepseek-harness.webp"),
            .init(id: "deepseek-apron", title: "盛装礼裙", urlString: "https://img.aigengtu.com/meme/1964.png"),
            .init(id: "deepseek-greet", title: "挥手致意", urlString: "https://img.aigengtu.com/meme/2713.webp"),
            .init(id: "deepseek-reach", title: "Q版搭档", urlString: "https://img.aigengtu.com/meme/1443.jpg"),
            .init(id: "deepseek-maid", title: "执勤侧影", urlString: "https://img.aigengtu.com/meme/057.webp"),
        ]
    )
    static let claude = AIGijinkaCharacter(
        id: "claude",
        name: "Claude",
        brand: "Claude",
        accentHex: "#D97757",
        artworks: [
            .init(id: "claude-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/claude.webp?v=20261114"),
            .init(id: "claude-tome", title: "黑金典籍", urlString: "https://img.aigengtu.com/meme/3050.png"),
            .init(id: "claude-dress", title: "暖黄洋装", urlString: "https://img.aigengtu.com/meme/1757.png"),
        ]
    )
    static let gpt = AIGijinkaCharacter(
        id: "gpt",
        name: "GPT",
        brand: "OpenAI GPT",
        accentHex: "#10A37F",
        artworks: [
            .init(id: "gpt-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/gpt.webp?v=20261114"),
            .init(id: "gpt-astra", title: "GPT-6 Astra", urlString: "https://img.aigengtu.com/refs/gj-gpt-astra.webp"),
            .init(id: "gpt-mint", title: "青翠制服", urlString: "https://img.aigengtu.com/meme/2180.png"),
            .init(id: "gpt-jade", title: "薄荷长裙", urlString: "https://img.aigengtu.com/meme/2194.png"),
            .init(id: "gpt-emerald", title: "翡翠礼装", urlString: "https://img.aigengtu.com/meme/2198.png"),
        ]
    )
    static let gemini = AIGijinkaCharacter(
        id: "gemini",
        name: "Gemini",
        brand: "Gemini",
        accentHex: "#6366F1",
        artworks: [
            .init(id: "gemini-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/gemini.webp?v=20261114"),
            .init(id: "gemini-crown", title: "星冠礼装", urlString: "https://img.aigengtu.com/meme/3040.png"),
            .init(id: "gemini-prism", title: "双子虹彩", urlString: "https://img.aigengtu.com/meme/2175.png"),
        ]
    )
    static let qwen = AIGijinkaCharacter(
        id: "qwen",
        name: "Qwen",
        brand: "Qwen",
        accentHex: "#7C5CFC",
        artworks: [
            .init(id: "qwen-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/qwen.webp?v=20261114"),
            .init(id: "qwen-headset", title: "轻装耳机版", urlString: "https://img.aigengtu.com/meme/2222.png"),
        ]
    )
    static let kimi = AIGijinkaCharacter(
        id: "kimi",
        name: "Kimi",
        brand: "Kimi",
        accentHex: "#2563EB",
        artworks: [
            .init(id: "kimi-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/kimi.webp?v=20261114"),
            .init(id: "kimi-lolita", title: "深蓝星夜", urlString: "https://img.aigengtu.com/meme/2933.png"),
            .init(id: "kimi-flute", title: "月下长笛", urlString: "https://img.aigengtu.com/meme/3054.png"),
        ]
    )
    static let glm = AIGijinkaCharacter(
        id: "glm",
        name: "GLM",
        brand: "GLM",
        accentHex: "#4F46E5",
        artworks: [
            .init(id: "glm-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/glm.webp?v=20261114"),
            .init(id: "glm-mono", title: "黑白构成", urlString: "https://img.aigengtu.com/meme/3046.png", cropAnchor: .center),
        ]
    )
    static let minimax = AIGijinkaCharacter(
        id: "minimax",
        name: "MiniMax",
        brand: "MiniMax",
        accentHex: "#F97316",
        artworks: [
            .init(id: "minimax-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/minimax.webp?v=20261114"),
            .init(id: "minimax-conch", title: "海螺领航", urlString: "https://img.aigengtu.com/meme/1394.jpeg"),
        ]
    )
    static let grok = AIGijinkaCharacter(
        id: "grok",
        name: "Grok",
        brand: "Grok",
        accentHex: "#E11D48",
        artworks: [
            .init(id: "grok-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/grok.webp?v=20261114"),
            .init(id: "grok-gothic", title: "暗夜礼装", urlString: "https://img.aigengtu.com/meme/2204.png"),
        ]
    )
    static let seed = AIGijinkaCharacter(
        id: "seed",
        name: "Seed",
        brand: "Seed",
        accentHex: "#14B8A6",
        artworks: [
            .init(id: "seed-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/doubao.webp?v=20261114"),
        ]
    )
    static let stepfun = AIGijinkaCharacter(
        id: "stepfun",
        name: "StepFun",
        brand: "StepFun",
        accentHex: "#6366F1",
        artworks: [
            .init(id: "stepfun-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/stepfun.webp?v=20261114"),
            .init(id: "stepfun-lantern", title: "提灯披风", urlString: "https://img.aigengtu.com/meme/2228.png"),
        ]
    )
    static let mimo = AIGijinkaCharacter(
        id: "mimo",
        name: "MiMo",
        brand: "Xiaomi MiMo",
        accentHex: "#FF6900",
        artworks: [
            .init(id: "mimo-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/mimo.webp?v=20261114"),
            .init(id: "mimo-bunny", title: "活力立绘", urlString: "https://img.aigengtu.com/meme/2210.png"),
        ]
    )
    static let llama = AIGijinkaCharacter(
        id: "llama",
        name: "Llama",
        brand: "Llama",
        accentHex: "#0284C7",
        artworks: [
            .init(id: "llama-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/llama.webp?v=20261114"),
        ]
    )
    static let mistral = AIGijinkaCharacter(
        id: "mistral",
        name: "Mistral",
        brand: "Mistral",
        accentHex: "#EA580C",
        artworks: [
            .init(id: "mistral-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/mistral.webp?v=20261114"),
        ]
    )
    static let perplexity = AIGijinkaCharacter(
        id: "perplexity",
        name: "Perplexity",
        brand: "Perplexity",
        accentHex: "#0EA5E9",
        artworks: [
            .init(id: "perplexity-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/perplexity.webp?v=20261114"),
        ]
    )
    static let rwkv = AIGijinkaCharacter(
        id: "rwkv",
        name: "RWKV",
        brand: "RWKV",
        accentHex: "#6D28D9",
        artworks: [
            .init(id: "rwkv-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/rwkv.webp?v=20261114"),
        ]
    )
    static let wenxin = AIGijinkaCharacter(
        id: "wenxin",
        name: "ERNIE",
        brand: "ERNIE",
        accentHex: "#2563EB",
        artworks: [
            .init(id: "wenxin-portrait", title: "标准立绘", urlString: "https://img.aigengtu.com/refs/gj-wenxin.webp"),
        ]
    )
    static let hunyuan = AIGijinkaCharacter(
        id: "hunyuan",
        name: "Hunyuan",
        brand: "Hunyuan",
        accentHex: "#0EA5E9",
        artworks: [
            .init(id: "hunyuan-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/hunyuan.webp?v=20261114"),
        ]
    )
    static let image2 = AIGijinkaCharacter(
        id: "image2",
        name: "Image 2",
        brand: "Image 2",
        accentHex: "#334155",
        artworks: [
            .init(id: "image2-portrait", title: "标准立绘", urlString: "https://img.aigengtu.com/refs/gj-gpt-image2.webp"),
        ]
    )
    static let opencode = AIGijinkaCharacter(
        id: "opencode",
        name: "OpenCode",
        brand: "OpenCode",
        accentHex: "#475569",
        artworks: [
            .init(id: "opencode-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/opencode.webp?v=20261114"),
        ]
    )
    static let huggingface = AIGijinkaCharacter(
        id: "huggingface",
        name: "Hugging Face",
        brand: "Hugging Face",
        accentHex: "#F59E0B",
        artworks: [
            .init(id: "huggingface-portrait", title: "标准立绘", urlString: "https://aigengtu.com/public/assets/characters/huggingface.webp?v=20261114"),
        ]
    )
    
    static let allCharacters: [AIGijinkaCharacter] = [
        .deepseek, .qwen, .claude, .gpt, .gemini, .kimi, .glm, .minimax,
        .grok, .seed, .stepfun, .mimo, .llama, .mistral, .perplexity,
        .rwkv, .wenxin, .hunyuan, .image2, .opencode, .huggingface,
    ]
    
    
    /// Resolves the Bot visual suite strictly from the user-selected model ID first,
    /// falling back to the gateway display name / base URL only when the model ID itself is generic.
    static func resolve(
        modelName: String?,
        endpointName: String? = nil,
        baseURL: String? = nil
    ) -> AIGijinkaCharacter? {
        if let model = modelName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !model.isEmpty,
           let matched = Self.matchBrand(in: model)
        {
            return matched
        }
        let hint = [endpointName, baseURL]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !hint.isEmpty {
            return Self.matchBrand(in: hint)
        }
        return nil
    }
    
    
    private static func matchBrand(in raw: String) -> AIGijinkaCharacter? {
        let lower = raw.lowercased()
        
        if lower.contains("deepseek") || lower.contains("深度求索") { return .deepseek }
        if lower.contains("claude") || lower.contains("anthropic") || lower.contains("sonnet") || lower.contains("opus") || lower.contains("haiku") { return .claude }
        if lower.contains("qwen") || lower.contains("qwq") || lower.contains("tongyi") || lower.contains("dashscope") || lower.contains("千问") || lower.contains("通义") { return .qwen }
        if lower.contains("gemini") || lower.contains("gemma") || lower.contains("generativelanguage.googleapis") { return .gemini }
        if lower.contains("kimi") || lower.contains("moonshot") || lower.contains("月之暗面") { return .kimi }
        if lower.contains("glm") || lower.contains("zhipu") || lower.contains("bigmodel") || lower.contains("智谱") { return .glm }
        if lower.contains("minimax") || lower.contains("abab") || lower.contains("hailuo") { return .minimax }
        if lower.contains("grok") || lower.contains("api.x.ai") || lower.contains("xai/") { return .grok }
        if lower.contains("seed") || lower.contains("doubao") || lower.contains("豆包") || lower.contains("volces") || lower.contains("bytedance") { return .seed }
        if lower.contains("stepfun") || lower.contains("step-") || lower.contains("阶跃") { return .stepfun }
        if lower.contains("mimo") || lower.contains("xiaomi") || lower.contains("小米") { return .mimo }
        if lower.contains("llama") || lower.contains("meta-llama") { return .llama }
        if lower.contains("mistral") || lower.contains("mixtral") || lower.contains("codestral") || lower.contains("pixtral") { return .mistral }
        if lower.contains("perplexity") || lower.contains("sonar") { return .perplexity }
        if lower.contains("rwkv") { return .rwkv }
        if lower.contains("ernie") || lower.contains("wenxin") || lower.contains("文心") || lower.contains("qianfan") { return .wenxin }
        if lower.contains("hunyuan") || lower.contains("混元") { return .hunyuan }
        if lower.contains("gpt-image") || lower.contains("image-2") || lower.contains("image 2") { return .image2 }
        if lower.contains("gpt") || lower.contains("openai") || lower.contains("chatgpt") || lower.contains("codex")
            || lower.range(of: #"(^|[/\-_\s])o[134]($|[/\-_\s\.])"#, options: .regularExpression) != nil
        {
            return .gpt
        }
        if lower.contains("opencode") { return .opencode }
        if lower.contains("huggingface") || lower.contains("hf.co") { return .huggingface }
        return nil
    }
}


/// Artwork loader resolving bundled HD static `Assets.xcassets/BotAvatars` resources first,
/// with automatic local cache & URL fallback if ever needed.
@MainActor @Observable
final class AIGijinkaImageLoader {
    
    static let shared = AIGijinkaImageLoader()
    
    private(set) var images: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    private let cacheDirectory: URL
    
    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        self.cacheDirectory = caches
            .appending(path: "CotEditor", directoryHint: .isDirectory)
            .appending(path: "BotAvatars", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }
    
    
    func image(for artwork: AIGijinkaArtwork) -> NSImage? {
        let key = artwork.id
        if let cached = self.images[key] {
            return cached
        }
        if !artwork.assetName.isEmpty,
           let bundled = NSImage(named: NSImage.Name(artwork.assetName))
               ?? Bundle(for: AIGijinkaImageLoader.self).image(forResource: NSImage.Name(artwork.assetName))
        {
            self.images[key] = bundled
            return bundled
        }
        let diskURL = self.cacheDirectory.appending(path: "\(key).webp")
        if let diskImage = NSImage(contentsOf: diskURL) {
            self.images[key] = diskImage
            return diskImage
        }
        self.triggerFetchIfNeeded(for: artwork)
        return nil
    }
    
    
    func image(for character: AIGijinkaCharacter) -> NSImage? {
        guard let primary = character.artworks.first else { return nil }
        return self.image(for: primary)
    }
    
    
    func prefetch(_ artworks: [AIGijinkaArtwork]) {
        for artwork in Set(artworks) {
            _ = self.image(for: artwork)
        }
    }
    
    
    func prefetch(_ characters: [AIGijinkaCharacter]) {
        for character in Set(characters) {
            _ = self.image(for: character)
        }
    }
    
    
    private func triggerFetchIfNeeded(for artwork: AIGijinkaArtwork) {
        let key = artwork.id
        guard !self.inFlight.contains(key),
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let url = artwork.url
        else { return }
        
        self.inFlight.insert(key)
        let diskURL = self.cacheDirectory.appending(path: "\(key).webp")
        
        Task.detached(priority: .utility) {
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
            request.setValue("image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = NSImage(data: data)
            else {
                await MainActor.run {
                    _ = AIGijinkaImageLoader.shared.inFlight.remove(key)
                }
                return
            }
            try? data.write(to: diskURL, options: .atomic)
            await MainActor.run {
                AIGijinkaImageLoader.shared.images[key] = decoded
                _ = AIGijinkaImageLoader.shared.inFlight.remove(key)
            }
        }
    }
}


/// Specialized Bot identity managed by the `Pi` kernel, representing a distinct editor capability.
nonisolated enum AIBotID: String, CaseIterable, Identifiable, Codable, Sendable {
    
    case ghost
    case translate
    case summarize
    case explain
    case weeklyReport
    case weeklyReportItem
    case interactiveChart
    case ocrPolish
    case organizeAndMerge
    case persona
    
    var id: String { self.rawValue }
    
    
    init(action: AIAction) {
        
        switch action {
            case .translate: self = .translate
            case .summarize: self = .summarize
            case .explain: self = .explain
            case .weeklyReport: self = .weeklyReport
            case .weeklyReportItem: self = .weeklyReportItem
            case .interactiveChart: self = .interactiveChart
            case .ocrPolish: self = .ocrPolish
            case .organizeAndMerge: self = .organizeAndMerge
        }
    }
    
    
    var linkedAction: AIAction? {
        
        switch self {
            case .translate: .translate
            case .summarize: .summarize
            case .explain: .explain
            case .weeklyReport: .weeklyReport
            case .weeklyReportItem: .weeklyReportItem
            case .interactiveChart: .interactiveChart
            case .ocrPolish: .ocrPolish
            case .organizeAndMerge: .organizeAndMerge
            case .ghost, .persona: nil
        }
    }
    
    
    var defaultPiToolProfile: PiBotToolProfile {
        switch self {
            case .ghost, .translate, .summarize, .explain, .weeklyReportItem, .persona:
                .pureChat
            case .weeklyReport, .interactiveChart, .ocrPolish:
                .workspaceRead
            case .organizeAndMerge:
                .autonomousAgent
        }
    }
    
    
    var handle: String {
        
        switch self {
            case .ghost: "@GhostBot"
            case .translate: "@TranslateBot"
            case .summarize: "@SummaryBot"
            case .explain: "@ExplainBot"
            case .weeklyReport: "@WeeklyBot"
            case .weeklyReportItem: "@SnippetBot"
            case .interactiveChart: "@ChartBot"
            case .ocrPolish: "@OCRBot"
            case .organizeAndMerge: "@TidyBot"
            case .persona: "@PersonaBot"
        }
    }
    
    
    var displayName: String {
        
        switch self {
            case .ghost: "续写幽灵"
            case .translate: "双语翻译官"
            case .summarize: "极简提炼师"
            case .explain: "大白话解释官"
            case .weeklyReport: "周报搭子"
            case .weeklyReportItem: "周报速记员"
            case .interactiveChart: "图表画师"
            case .ocrPolish: "识图整理员"
            case .organizeAndMerge: "工作区整理师"
            case .persona: "性格观察员"
        }
    }
    
    
    var tagline: String {
        
        switch self {
            case .ghost: "光标后静默预测半句，按 Tab 一次落笔"
            case .translate: "中英地道互译，保留代码与格式骨架"
            case .summarize: "剥离铺垫，提炼高信噪比纯文本要点"
            case .explain: "去掉黑话与术语堆砌，几句话讲清重点"
            case .weeklyReport: "聚合片段并参考历史文风，直接说人话"
            case .weeklyReportItem: "选中记录一秒收编进本周周报素材库"
            case .interactiveChart: "把表格或杂乱数字变成可交互 HTML 图表"
            case .ocrPolish: "结合本地 OCR 与视觉纠错还原表格代码"
            case .organizeAndMerge: "多窗口零散草稿归类合并并重起正经标题"
            case .persona: "每 6 小时静默感知写作习惯，凝练个性弹幕"
        }
    }
    
    
    var symbolName: String {
        
        switch self {
            case .ghost: "bolt.horizontal.fill"
            case .translate: "character.bubble.fill"
            case .summarize: "text.alignleft"
            case .explain: "lightbulb.fill"
            case .weeklyReport: "calendar.badge.checkmark"
            case .weeklyReportItem: "text.badge.plus"
            case .interactiveChart: "chart.xyaxis.line"
            case .ocrPolish: "doc.text.viewfinder"
            case .organizeAndMerge: "square.stack.3d.up.fill"
            case .persona: "theatermasks.fill"
        }
    }
    
    
    var accentHex: String {
        switch self {
            case .ghost: "#10B981"
            case .translate: "#3B82F6"
            case .summarize: "#6366F1"
            case .explain: "#F59E0B"
            case .weeklyReport: "#0EA5E9"
            case .weeklyReportItem: "#14B8A6"
            case .interactiveChart: "#EC4899"
            case .ocrPolish: "#8B5CF6"
            case .organizeAndMerge: "#F97316"
            case .persona: "#E11D48"
        }
    }
    
    
    var analyticsFeatureKey: String {
        
        switch self {
            case .ghost: "nextToken"
            case .persona: "personalityAnalyze"
            default: self.linkedAction?.analyticsKey ?? self.rawValue
        }
    }
    
    
    var defaultSampleInput: String {
        
        switch self {
            case .ghost: "今天把设置界面重写了一遍，接下来"
            case .translate: "The local SQLite migration now preserves all API gateways, keys, and user avatars."
            case .summarize: "本周重构了设置窗口为侧边栏模式，补全了本地数据库迁移时对 API Key 和头像的备份，同时修复了 Vim Visual 模式下 j/k 移动留下的 1px 残影问题。"
            case .explain: "通过对 CAShapeLayer 显式绑定 shadowPath 并对 Selection 变动范围做上下 6pt 像素对齐重绘，消除亚像素残影。"
            case .weeklyReport: "1. 修复了分屏放大下的快捷键冲突\n2. 完成了个人数据看板重构\n3. 优化了本地词库续写"
            case .weeklyReportItem: "给个人设置加了 ASCII 通行证和 5 套主题配色，支持导出 PNG"
            case .interactiveChart: "周一: 1800字, 周二: 2400字, 周三: 3100字, 周四: 1500字, 周五: 2700字"
            case .ocrPolish: "CotEditor 7.O  设 置 -> Bots\n网 关 : deepseek-chat  延 迟 210 ms"
            case .organizeAndMerge: "草稿1：周末去买咖啡豆；草稿2：下周先把设置页精简和数据库迁移写完，再测试单副本构建。"
            case .persona: "常在深夜写技术总结，喜欢用直白短句和分点，写完代码必先测试再 commit 推送。"
        }
    }
    
    
    var defaultSystemPrompt: String {
        
        if let action = self.linkedAction {
            return action.defaultSystemPrompt
        }
        switch self {
            case .ghost:
                return "你是嵌入编辑器光标处的续写幽灵。只接续光标后最自然的半句或短词，不重复前文，不加引号与解释。"
            case .persona:
                return """
                你是一位敏锐、幽默但不刻薄的私人写作观察员。阅读用户近期写下的文字与习惯，提炼出最贴切的人物概念标题、深入理解与 5~7 个不超过 8 个汉字的个性弹幕标签（如「深夜架构狂」「极简主义者」「说人话专家」）。严格输出 JSON，不添油加醋。
                """
            default:
                return ""
        }
    }
}


/// Per-bot persisted configuration (enabled toggle, dedicated gateway & model override,
/// tone/persona, temperature, artwork variant index, and `Pi` tool profile).
nonisolated struct AIBotConfig: Codable, Sendable, Equatable {
    
    var isEnabled: Bool = true
    var endpointID: UUID? = nil
    var modelOverride: String = ""
    var customPersona: String = ""
    var temperature: Double? = nil
    var artworkVariantIndex: Int? = nil
    var toolProfile: PiBotToolProfile? = nil
    
    
    init(
        isEnabled: Bool = true,
        endpointID: UUID? = nil,
        modelOverride: String = "",
        customPersona: String = "",
        temperature: Double? = nil,
        artworkVariantIndex: Int? = nil,
        toolProfile: PiBotToolProfile? = nil
    ) {
        self.isEnabled = isEnabled
        self.endpointID = endpointID
        self.modelOverride = modelOverride
        self.customPersona = customPersona
        self.temperature = temperature
        self.artworkVariantIndex = artworkVariantIndex
        self.toolProfile = toolProfile
    }
    
    
    func effectiveToolProfile(for botID: AIBotID) -> PiBotToolProfile {
        self.toolProfile ?? botID.defaultPiToolProfile
    }
    
    
    enum CodingKeys: String, CodingKey {
        case isEnabled, endpointID, modelOverride, customPersona, temperature, artworkVariantIndex, toolProfile
    }
    
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.endpointID = try container.decodeIfPresent(UUID.self, forKey: .endpointID)
        self.modelOverride = try container.decodeIfPresent(String.self, forKey: .modelOverride) ?? ""
        self.customPersona = try container.decodeIfPresent(String.self, forKey: .customPersona) ?? ""
        self.temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        self.artworkVariantIndex = try container.decodeIfPresent(Int.self, forKey: .artworkVariantIndex)
        self.toolProfile = try container.decodeIfPresent(PiBotToolProfile.self, forKey: .toolProfile)
    }
}


/// Manages per-bot settings, prompts, model routing, and `PiKernelManager` synchronization backed by `CotLocalDatabase`.
@MainActor @Observable final class AIBotStore {
    
    static let shared = AIBotStore()
    
    struct PersonaPreset: Identifiable, Sendable {
        let id: String
        let title: String
        let prompt: String
    }
    
    static let personaPresets: [PersonaPreset] = [
        .init(id: "expert",
              title: "精炼技术专家",
              prompt: "严谨资深的系统工程师，回答直击本质、注重准确性与高信噪比，避免空话和冗余铺垫。"),
        .init(id: "weekly",
              title: "直白周报搭档",
              prompt: "高效务实的研发协作伙伴，善于把零散工作记录提炼为清晰、实在、不堆砌套话的周报总结。"),
        .init(id: "architect",
              title: "深度架构顾问",
              prompt: "擅长从边界设计、并发安全、可维护性与性能权衡角度审视方案的架构顾问，兼顾落地成本与长期演进。"),
        .init(id: "editor",
              title: "双语润色编辑",
              prompt: "兼具中文书面表达功底与英文技术术语准确性的编辑，善于梳理文档结构、消除翻译腔并提升可读性。"),
    ]
    
    private(set) var configs: [String: AIBotConfig] = [:]
    private let database: CotLocalDatabase
    
    
    init(database: CotLocalDatabase = .shared) {
        self.database = database
        self.reloadFromDatabase()
    }
    
    
    func reloadFromDatabase() {
        
        let raw = self.database.string(forKey: CotLocalDatabase.ConfigKey.aiBotsConfigJSON)
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: AIBotConfig].self, from: data)
        else {
            self.configs = [:]
            return
        }
        self.configs = decoded
    }
    
    
    func config(for botID: AIBotID) -> AIBotConfig {
        
        var config = self.configs[botID.rawValue] ?? AIBotConfig()
        if botID == .ghost {
            config.isEnabled = self.database.bool(forKey: CotLocalDatabase.ConfigKey.aiNextTokenEnabled, default: true)
            let ghostOverride = self.database.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenModelOverride)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if config.modelOverride.isEmpty, !ghostOverride.isEmpty {
                config.modelOverride = ghostOverride
            }
        } else if botID == .persona {
            config.isEnabled = self.database.bool(forKey: CotLocalDatabase.ConfigKey.aiPersonalityAutoEnabled, default: true)
        }
        return config
    }
    
    
    func updateConfig(_ config: AIBotConfig, for botID: AIBotID) {
        
        var clean = config
        clean.modelOverride = config.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        self.configs[botID.rawValue] = clean
        
        if botID == .ghost {
            self.database.set(clean.isEnabled, forKey: CotLocalDatabase.ConfigKey.aiNextTokenEnabled)
            if self.database === CotLocalDatabase.shared {
                UserDefaults.standard.set(clean.isEnabled, forKey: CotLocalDatabase.ConfigKey.aiNextTokenEnabled)
            }
            self.database.set(clean.modelOverride, forKey: CotLocalDatabase.ConfigKey.aiNextTokenModelOverride)
            if self.database === CotLocalDatabase.shared {
                UserDefaults.standard.set(clean.modelOverride, forKey: CotLocalDatabase.ConfigKey.aiNextTokenModelOverride)
            }
        } else if botID == .persona {
            self.database.set(clean.isEnabled, forKey: CotLocalDatabase.ConfigKey.aiPersonalityAutoEnabled)
        }
        
        if let data = try? JSONEncoder().encode(self.configs),
           let json = String(data: data, encoding: .utf8)
        {
            self.database.set(json, forKey: CotLocalDatabase.ConfigKey.aiBotsConfigJSON)
        }
        
        if self.database === CotLocalDatabase.shared {
            _ = try? PiKernelManager.shared.syncWorkspace()
        }
    }
    
    
    func systemPrompt(for botID: AIBotID) -> String {
        
        if let action = botID.linkedAction {
            return self.database.customStagePrompt(forKey: action.databaseConfigKey)
                ?? action.defaultSystemPrompt
        }
        let custom = self.database.string(forKey: "ai.bot.\(botID.rawValue).prompt")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? botID.defaultSystemPrompt : custom
    }
    
    
    func setSystemPrompt(_ prompt: String, for botID: AIBotID) {
        
        if let action = botID.linkedAction {
            self.database.set(prompt, forKey: action.databaseConfigKey)
        } else {
            self.database.set(prompt, forKey: "ai.bot.\(botID.rawValue).prompt")
        }
        if self.database === CotLocalDatabase.shared {
            _ = try? PiKernelManager.shared.syncWorkspace()
        }
    }
    
    
    func resetBotToDefaults(_ botID: AIBotID) {
        
        self.setSystemPrompt(botID.defaultSystemPrompt, for: botID)
        self.updateConfig(AIBotConfig(), for: botID)
    }
    
    
    /// Resolves the target `AIEndpointProfile` for `botID`, falling back to the active gateway.
    func resolvedEndpointProfile(
        for botID: AIBotID,
        endpoints: [AIEndpointProfile]? = nil
    ) -> AIEndpointProfile? {
        let profiles = endpoints ?? AIEndpointStore.profiles
        let botConfig = self.config(for: botID)
        if let targetID = botConfig.endpointID,
           let matched = profiles.first(where: { $0.id == targetID })
        {
            return matched
        }
        let activeID = AIEndpointStore.activeID ?? profiles.first?.id
        return profiles.first(where: { $0.id == activeID }) ?? profiles.first
    }
    
    
    /// Resolves the effective `AIConfiguration` for a bot, honoring any per-bot gateway selection,
    /// model override, and temperature.
    func resolvedConfiguration(
        for botID: AIBotID,
        baseConfig: AIConfiguration? = nil,
        endpoints: [AIEndpointProfile]? = nil
    ) -> AIConfiguration {
        
        let botConfig = self.config(for: botID)
        var resolved: AIConfiguration
        if let targetEndpointID = botConfig.endpointID,
           let matchedEndpoint = (endpoints ?? AIEndpointStore.profiles).first(where: { $0.id == targetEndpointID })
        {
            resolved = matchedEndpoint.configuration(apiKey: AIEndpointStore.apiKey(for: matchedEndpoint))
        } else {
            resolved = baseConfig ?? AIConfiguration.current
        }
        if !botConfig.modelOverride.isEmpty {
            resolved.model = botConfig.modelOverride
        }
        if let temp = botConfig.temperature {
            resolved.temperature = temp
        }
        return resolved
    }
}
