#!/usr/bin/env swift

import CryptoKit
import Foundation
import ImageIO
import SQLite3
import Vision

struct IndexEntry: Decodable {
    let file: String
    let category: String
    let format: String
    let width: Int
    let height: Int
    let bytes: Int
    let sha256: String
    let source_site: String?
    let source_url: String?
}

func normalizeCategory(_ raw: String) -> String {
    let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if lower.contains("deepseek") { return "deepseek" }
    if lower.contains("claude") { return "claude" }
    if lower.contains("openai") || lower.contains("gpt") { return "openai" }
    if lower.contains("gemini") { return "gemini" }
    if lower.contains("cat") { return "cat" }
    if lower.contains("dog") { return "dog" }
    if lower.contains("baoman") { return "baoman" }
    if lower.contains("reaction") { return "reaction" }
    return "custom"
}

func defaultMoods(for cat: String) -> [String] {
    switch cat {
        case "deepseek": ["开心", "摸鱼", "专注"]
        case "claude": ["平静", "专注", "暖心"]
        case "openai": ["开心", "兴奋", "专注"]
        case "gemini": ["兴奋", "开心", "平静"]
        case "cat": ["摸鱼", "无语", "委屈", "开心"]
        case "dog": ["开心", "委屈", "摸鱼"]
        case "baoman": ["无语", "兴奋", "委屈"]
        case "reaction": ["无语", "开心", "平静"]
        default: ["开心", "平静"]
    }
}

let moodRules: [(String, [String])] = [
    ("开心", ["开心", "哈哈", "笑", "nice", "good", "棒", "爽", "快乐", "耶", "赞", "喜欢", "爱", "可爱", "冲"]),
    ("兴奋", ["冲", "牛", "厉害", "起飞", "震惊", "卧槽", "绝了", "稳", "太强", "nb", "666"]),
    ("无语", ["无语", "汗", "裂开", "服了", "啊？", "什么", "离谱", "不懂", "呆", "沉默", "算了", "?", "？"]),
    ("委屈", ["哭", "泪", "难受", "委屈", "求", "救命", "崩", "累", "痛", "困", "惨", "寄"]),
    ("摸鱼", ["摸鱼", "躺", "睡", "困", "下班", "咖啡", "摸", "发呆", "摆烂"]),
    ("专注", ["思考", "想", "研究", "看", "写", "代码", "工作", "盯", "查", "认真", "学习"]),
    ("平静", ["好", "行", "ok", "嗯", "收到", "明白", "喝茶", "淡定"]),
]

func inferMoodsAndTags(cat: String, ocr: String) -> ([String], [String]) {
    let lower = ocr.lowercased()
    var moods: [String] = []
    for (m, kws) in moodRules where kws.contains(where: { lower.contains($0) }) {
        moods.append(m)
    }
    if moods.isEmpty { moods = defaultMoods(for: cat) }
    var tags: [String] = [cat]
    for line in ocr.components(separatedBy: .newlines) {
        let c = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.count >= 2 && c.count <= 16 && !tags.contains(c) {
            tags.append(c)
        }
    }
    return (Array(moods.prefix(4)), Array(tags.prefix(10)))
}

func runOCR(at url: URL) -> String {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { return "" }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = true
    req.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    try? handler.perform([req])
    let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    return lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
}

func resolveActiveDBPath(home: URL) -> URL {
    let cotRoot = home.appending(path: "Library/Application Support/Cot", directoryHint: .isDirectory)
    let accountsDBPath = cotRoot.appending(path: "cot_accounts.sqlite3").path(percentEncoded: false)
    var db: OpaquePointer?
    if FileManager.default.fileExists(atPath: accountsDBPath),
       sqlite3_open(accountsDBPath, &db) == SQLITE_OK
    {
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql = "SELECT p.db_filename FROM profiles p JOIN meta m ON m.value = p.id WHERE m.key = 'active_profile_id' LIMIT 1;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW,
           let cStr = sqlite3_column_text(stmt, 0)
        {
            let filename = String(cString: cStr)
            sqlite3_finalize(stmt)
            return cotRoot.appending(path: filename)
        }
        sqlite3_finalize(stmt)
    }
    return cotRoot.appending(path: "cot_user_data.sqlite3")
}

let home = FileManager.default.homeDirectoryForCurrentUser
let sourceRoot = home.appending(path: "Downloads/meme", directoryHint: .isDirectory)
let indexURL = sourceRoot.appending(path: "index.json")
let stickersRoot = home.appending(path: "Library/Application Support/CotEditor/MediaLibrary/stickers", directoryHint: .isDirectory)
let dbURL = resolveActiveDBPath(home: home)

guard let indexData = try? Data(contentsOf: indexURL),
      let entries = try? JSONDecoder().decode([IndexEntry].self, from: indexData)
else {
    fputs("Failed to read \(indexURL.path)\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: stickersRoot, withIntermediateDirectories: true)

var db: OpaquePointer?
guard sqlite3_open(dbURL.path(percentEncoded: false), &db) == SQLITE_OK else {
    fputs("Failed to open SQLite DB at \(dbURL.path)\n", stderr)
    exit(1)
}
defer { sqlite3_close(db) }

let createSQL = """
CREATE TABLE IF NOT EXISTS user_stickers (
    id TEXT PRIMARY KEY,
    file_name TEXT NOT NULL,
    category TEXT NOT NULL,
    format TEXT NOT NULL,
    width INTEGER NOT NULL DEFAULT 0,
    height INTEGER NOT NULL DEFAULT 0,
    bytes INTEGER NOT NULL DEFAULT 0,
    sha256 TEXT NOT NULL UNIQUE,
    ocr_text TEXT NOT NULL DEFAULT '',
    meaning TEXT NOT NULL DEFAULT '',
    moods_json TEXT NOT NULL DEFAULT '[]',
    tags_json TEXT NOT NULL DEFAULT '[]',
    source_site TEXT NOT NULL DEFAULT '',
    source_url TEXT NOT NULL DEFAULT '',
    is_favorite INTEGER NOT NULL DEFAULT 0,
    use_count INTEGER NOT NULL DEFAULT 0,
    last_used_at REAL,
    created_at REAL NOT NULL
);
"""
sqlite3_exec(db, createSQL, nil, nil, nil)
sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil)

let upsertSQL = """
INSERT INTO user_stickers (
    id, file_name, category, format, width, height, bytes, sha256,
    ocr_text, meaning, moods_json, tags_json, source_site, source_url,
    is_favorite, use_count, last_used_at, created_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, '', ?, ?, ?, ?, 0, 0, NULL, ?)
ON CONFLICT(sha256) DO UPDATE SET
    category = excluded.category,
    ocr_text = CASE WHEN excluded.ocr_text != '' THEN excluded.ocr_text ELSE user_stickers.ocr_text END,
    moods_json = excluded.moods_json,
    tags_json = excluded.tags_json;
"""

var stmt: OpaquePointer?
guard sqlite3_prepare_v2(db, upsertSQL, -1, &stmt, nil) == SQLITE_OK else {
    fputs("Failed to prepare SQL\n", stderr)
    exit(1)
}

let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
let encoder = JSONEncoder()
let fm = FileManager.default
var imported = 0
var ocrHits = 0
let now = Date().timeIntervalSince1970

for entry in entries {
    let srcURL = sourceRoot.appending(path: entry.file)
    guard fm.fileExists(atPath: srcURL.path(percentEncoded: false)) else { continue }
    let cat = normalizeCategory(entry.category)
    let ext = srcURL.pathExtension.lowercased()
    let id = "stk_\(String(entry.sha256.prefix(16)))"
    let relPath = "\(cat)/\(id).\(ext)"
    let destURL = stickersRoot.appending(path: relPath)
    try? fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if !fm.fileExists(atPath: destURL.path(percentEncoded: false)) {
        try? fm.copyItem(at: srcURL, to: destURL)
    }
    let ocr = runOCR(at: srcURL)
    if !ocr.isEmpty { ocrHits += 1 }
    let (moods, tags) = inferMoodsAndTags(cat: cat, ocr: ocr)
    let moodsJSON = (try? encoder.encode(moods)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    let tagsJSON = (try? encoder.encode(tags)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    
    sqlite3_reset(stmt)
    sqlite3_clear_bindings(stmt)
    sqlite3_bind_text(stmt, 1, id, -1, transient)
    sqlite3_bind_text(stmt, 2, relPath, -1, transient)
    sqlite3_bind_text(stmt, 3, cat, -1, transient)
    sqlite3_bind_text(stmt, 4, entry.format, -1, transient)
    sqlite3_bind_int(stmt, 5, Int32(entry.width))
    sqlite3_bind_int(stmt, 6, Int32(entry.height))
    sqlite3_bind_int(stmt, 7, Int32(entry.bytes))
    sqlite3_bind_text(stmt, 8, entry.sha256, -1, transient)
    sqlite3_bind_text(stmt, 9, ocr, -1, transient)
    sqlite3_bind_text(stmt, 10, moodsJSON, -1, transient)
    sqlite3_bind_text(stmt, 11, tagsJSON, -1, transient)
    sqlite3_bind_text(stmt, 12, entry.source_site ?? "", -1, transient)
    sqlite3_bind_text(stmt, 13, entry.source_url ?? "", -1, transient)
    sqlite3_bind_double(stmt, 14, now)
    if sqlite3_step(stmt) == SQLITE_DONE {
        imported += 1
    }
}

sqlite3_finalize(stmt)
sqlite3_exec(db, "COMMIT;", nil, nil, nil)
print("Imported \(imported)/\(entries.count) stickers into \(dbURL.path(percentEncoded: false)) (Vision OCR text hits: \(ocrHits))")
