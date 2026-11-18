//
//  CotLogger.swift
//
//  CotEditor
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
import OSLog

/// Persistent rolling error logger keeping the most recent 7 days of daily logs
/// in `~/Library/Logs/Cot/cot-YYYY-MM-DD.log`.
final class CotLogger: @unchecked Sendable {
    
    enum Level: String, Sendable {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case fault = "FAULT"
    }
    
    enum Category: String, Sendable {
        case app = "App"
        case ai = "AI"
        case database = "Database"
        case document = "Document"
        case organizer = "Organizer"
        case ui = "UI"
    }
    
    static let shared = CotLogger()
    
    let logDirectoryURL: URL
    let retentionDays: Int
    
    private let nowProvider: @Sendable () -> Date
    private let queue = DispatchQueue(label: "local.cmy.Cot.CotLogger", qos: .utility)
    private let osLogger = Logger(subsystem: "local.cmy.Cot", category: "CotLogger")
    private let calendar: Calendar
    private let dayFormatter: DateFormatter
    private let timestampFormatter: DateFormatter
    private var lastPrunedDayKey: String?
    private static var hasInstalledHooks = false
    
    
    init(
        directoryURL: URL? = nil,
        retentionDays: Int = 7,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.retentionDays = max(1, retentionDays)
        self.nowProvider = nowProvider
        
        if let directoryURL {
            self.logDirectoryURL = directoryURL
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            self.logDirectoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("CotTestsLogs-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        } else {
            let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
                ?? URL.homeDirectory.appendingPathComponent("Library", isDirectory: true)
            self.logDirectoryURL = libraryURL.appendingPathComponent("Logs/Cot", isDirectory: true)
        }
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        self.calendar = cal
        
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.calendar = cal
        dayFormatter.timeZone = .current
        dayFormatter.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = dayFormatter
        
        let timestampFormatter = DateFormatter()
        timestampFormatter.locale = Locale(identifier: "en_US_POSIX")
        timestampFormatter.calendar = cal
        timestampFormatter.timeZone = .current
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        self.timestampFormatter = timestampFormatter
        
        self.ensureDirectoryExists()
    }
    
    
    /// URL for today's rolling log file (`cot-YYYY-MM-DD.log`).
    var currentLogFileURL: URL {
        self.logFileURL(for: self.nowProvider())
    }
    
    
    /// Prepares the log directory on app startup, prunes expired logs, and writes a fresh session banner.
    func prepareForLaunch(appVersion: String? = nil, buildNumber: String? = nil) {
        let version = appVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "?"
        let build = buildNumber
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? "?"
        
        self.queue.async {
            let now = self.nowProvider()
            self.ensureDirectoryExists()
            self.pruneExpiredLogsLocked(referenceDate: now)
            self.appendLineLocked(
                level: .info,
                category: .app,
                message: "=== Cot session started (v\(version), build \(build)) ===",
                date: now
            )
        }
    }
    
    
    /// Installs an uncaught Objective-C exception handler once per app process.
    func installCrashAndExceptionHooks() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard !Self.hasInstalledHooks else { return }
        Self.hasInstalledHooks = true
        
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.prefix(12).joined(separator: " | ")
            CotLogger.shared.logSynchronously(
                level: .fault,
                category: .app,
                "Uncaught NSException: \(exception.name.rawValue) - \(exception.reason ?? "unknown")",
                context: ["stack": stack]
            )
        }
    }
    
    
    func info(
        category: Category,
        _ message: String,
        context: [String: String] = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        self.log(.info, category: category, message, error: nil, context: context, file: file, line: line)
    }
    
    
    func warning(
        category: Category,
        _ message: String,
        error: (any Error)? = nil,
        context: [String: String] = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        self.log(.warning, category: category, message, error: error, context: context, file: file, line: line)
    }
    
    
    func error(
        category: Category,
        _ message: String,
        error: (any Error)? = nil,
        context: [String: String] = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        self.log(.error, category: category, message, error: error, context: context, file: file, line: line)
    }
    
    
    func log(
        _ level: Level,
        category: Category,
        _ message: String,
        error: (any Error)? = nil,
        context: [String: String] = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        let now = self.nowProvider()
        let formattedMessage = Self.composeMessage(
            message,
            error: error,
            context: context,
            file: file,
            line: line
        )
        
        switch level {
            case .info:
                self.osLogger.info("[\(category.rawValue, privacy: .public)] \(formattedMessage, privacy: .public)")
            case .warning:
                self.osLogger.warning("[\(category.rawValue, privacy: .public)] \(formattedMessage, privacy: .public)")
            case .error:
                self.osLogger.error("[\(category.rawValue, privacy: .public)] \(formattedMessage, privacy: .public)")
            case .fault:
                self.osLogger.fault("[\(category.rawValue, privacy: .public)] \(formattedMessage, privacy: .public)")
        }
        
        self.queue.async {
            self.appendLineLocked(level: level, category: category, message: formattedMessage, date: now)
        }
    }
    
    
    /// Writes a log entry synchronously (intended for crash hooks and unit tests).
    func logSynchronously(
        level: Level,
        category: Category,
        _ message: String,
        error: (any Error)? = nil,
        context: [String: String] = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        let now = self.nowProvider()
        let formattedMessage = Self.composeMessage(
            message,
            error: error,
            context: context,
            file: file,
            line: line
        )
        self.queue.sync {
            self.appendLineLocked(level: level, category: category, message: formattedMessage, date: now)
        }
    }
    
    
    /// Waits until all queued log writes and prunes have completed.
    func flush() {
        self.queue.sync { }
    }
    
    
    /// Explicitly prunes expired daily log files (exposed for testing and manual maintenance).
    func pruneExpiredLogs(referenceDate: Date? = nil) {
        self.queue.sync {
            self.pruneExpiredLogsLocked(referenceDate: referenceDate ?? self.nowProvider(), force: true)
        }
    }
    
    
    /// Returns all currently retained daily log file URLs sorted newest-first.
    func availableLogFiles() -> [URL] {
        self.queue.sync {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: self.logDirectoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            return contents
                .filter { Self.parseLogDay(fromFilename: $0.lastPathComponent, formatter: self.dayFormatter) != nil }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
    }
    
    
    /// Redacts API keys, bearer tokens, and query-string secrets from log text.
    static func redactSecrets(in text: String) -> String {
        guard !text.isEmpty else { return text }
        var output = text
        for (regex, replacement) in Self.redactionRules {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: replacement)
        }
        return output
    }
    
    
    // MARK: Private Helpers
    
    private func logFileURL(for date: Date) -> URL {
        let dayString = self.dayFormatter.string(from: date)
        return self.logDirectoryURL.appendingPathComponent("cot-\(dayString).log", isDirectory: false)
    }
    
    
    private func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(at: self.logDirectoryURL, withIntermediateDirectories: true)
    }
    
    
    private func appendLineLocked(level: Level, category: Category, message: String, date: Date) {
        self.ensureDirectoryExists()
        let dayKey = self.dayFormatter.string(from: date)
        if self.lastPrunedDayKey != dayKey {
            self.pruneExpiredLogsLocked(referenceDate: date, force: true)
            self.lastPrunedDayKey = dayKey
        }
        
        let timestamp = self.timestampFormatter.string(from: date)
        let sanitized = message
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " \\n ")
        let line = "[\(timestamp)] [\(level.rawValue)] [\(category.rawValue)] \(sanitized)\n"
        guard let data = line.data(using: .utf8) else { return }
        
        let fileURL = self.logDirectoryURL.appendingPathComponent("cot-\(dayKey).log", isDirectory: false)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: data, attributes: [.posixPermissions: 0o600])
            return
        }
        
        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            self.osLogger.error("Failed appending CotLogger entry: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    
    private func pruneExpiredLogsLocked(referenceDate: Date, force: Bool = false) {
        let dayKey = self.dayFormatter.string(from: referenceDate)
        if !force, self.lastPrunedDayKey == dayKey { return }
        self.lastPrunedDayKey = dayKey
        
        let todayStart = self.calendar.startOfDay(for: referenceDate)
        guard let cutoffDate = self.calendar.date(byAdding: .day, value: -(self.retentionDays - 1), to: todayStart) else { return }
        
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: self.logDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        
        for url in contents {
            guard let fileDate = Self.parseLogDay(fromFilename: url.lastPathComponent, formatter: self.dayFormatter) else {
                continue
            }
            if fileDate < cutoffDate {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
    
    
    private static func parseLogDay(fromFilename filename: String, formatter: DateFormatter) -> Date? {
        guard filename.hasPrefix("cot-"), filename.hasSuffix(".log") else { return nil }
        let start = filename.index(filename.startIndex, offsetBy: 4)
        let end = filename.index(filename.endIndex, offsetBy: -4)
        guard start < end else { return nil }
        let token = String(filename[start..<end])
        return formatter.date(from: token)
    }
    
    
    private static func composeMessage(
        _ message: String,
        error: (any Error)?,
        context: [String: String],
        file: String,
        line: Int
    ) -> String {
        var parts: [String] = []
        let sourceName = (file as NSString).lastPathComponent
        parts.append("\(Self.redactSecrets(in: message)) (\(sourceName):\(line))")
        
        if let error {
            let nsError = error as NSError
            let desc = Self.redactSecrets(in: error.localizedDescription)
            parts.append("error=[\(nsError.domain):\(nsError.code)] \(desc)")
        }
        
        if !context.isEmpty {
            let formattedContext = context.keys.sorted().compactMap { key -> String? in
                guard let value = context[key] else { return nil }
                return "\(key)=\(Self.redactSecrets(in: value))"
            }.joined(separator: ", ")
            if !formattedContext.isEmpty {
                parts.append(formattedContext)
            }
        }
        
        return parts.joined(separator: " | ")
    }
    
    
    private static let redactionRules: [(NSRegularExpression, String)] = {
        let patterns: [(String, String)] = [
            (#"oc_sk_[A-Za-z0-9_-]+"#, "oc_sk_***"),
            (#"user_[A-Za-z0-9_-]{12,}"#, "user_***"),
            (#"(?i)(authorization|x-api-key)\s*[:=]\s*(?:bearer\s+)?[A-Za-z0-9._-]{8,}"#, "$1: ***"),
            (#"(?i)\bbearer\s+[A-Za-z0-9._-]{8,}"#, "Bearer ***"),
            (#"\bsk-(?:ant-|proj-)?[A-Za-z0-9._-]{8,}"#, "sk-***"),
            (#"([?&]key=)[^&\s]+"#, "$1***"),
        ]
        return patterns.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, replacement)
        }
    }()
}
