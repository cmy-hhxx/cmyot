//
//  CotMarketDataClient.swift
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

nonisolated struct ParsedRealtimeQuote: Equatable, Sendable {
    
    let lastPrice: Double
    let previousClose: Double
    let dayOpen: Double
    let high: Double
    let low: Double
    let volume: Double
    let amount: Double?
    let turnoverRate: Double?
    let peRatio: Double?
    let marketCap: Double?
}


/// Resilient multi-source market data client combining Tencent Realtime (`qt.gtimg.cn`),
/// Eastmoney Push2His K-Line (`push2his.eastmoney.com`), Tencent `fqkline/get`, and Sina Finance fallbacks.
actor CotMarketDataClient {
    
    static let shared = CotMarketDataClient()
    
    private let session: URLSession
    private let searchToken = "D43BF722C8E33DA55D5C6812C6C46"
    private var usTencentSuffixCache: [String: String] = [:]
    
    
    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 16
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }
    
    
    // MARK: - Search (Alias Catalog + Eastmoney Suggest + Tencent Smartbox Fallback)
    
    func searchInstruments(matching rawQuery: String) async throws -> [MarketInstrument] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        
        var results: [MarketInstrument] = []
        var seen = Set<String>()
        
        if let aliasMatch = MarketAliasCatalog.resolve(query) {
            results.append(aliasMatch)
            seen.insert(aliasMatch.instrumentID)
        }
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "searchapi.eastmoney.com"
        components.path = "/api/suggest/get"
        components.queryItems = [
            URLQueryItem(name: "input", value: query),
            URLQueryItem(name: "type", value: "14"),
            URLQueryItem(name: "token", value: self.searchToken),
            URLQueryItem(name: "count", value: "20"),
        ]
        if let url = components.url,
           let data = try? await self.request(url, referer: "https://quote.eastmoney.com/"),
           let envelope = try? JSONDecoder().decode(EastMoneySuggestEnvelope.self, from: data)
        {
            for item in envelope.table.data {
                guard let parsed = Self.instrument(from: item) else { continue }
                if seen.insert(parsed.instrumentID).inserted {
                    results.append(parsed)
                }
            }
        }
        
        if results.isEmpty {
            let smartboxMatches = await self.searchTencentSmartbox(query: query)
            for item in smartboxMatches where seen.insert(item.instrumentID).inserted {
                results.append(item)
            }
        }
        return results
    }
    
    
    // MARK: - Multi-Source K-Line & Intraday Snapshot
    
    func fetchQuoteAndBars(
        for instrument: MarketInstrument,
        period: MarketChartPeriod
    ) async throws -> MarketQuoteSnapshot {
        let resolvedTencent = try await self.resolvedTencentCode(for: instrument)
        let tz = instrument.market.timeZone
        
        async let realtimeQuoteTask = self.fetchRealtimeQuoteWithFallback(instrument: instrument, tencentCode: resolvedTencent)
        async let intradayTask = self.fetchIntradayBars(instrument: instrument, tencentCode: resolvedTencent, timeZone: tz)
        async let periodTask = self.fetchSeriesBars(
            instrument: instrument,
            tencentCode: resolvedTencent,
            period: period == .intraday ? .day : period,
            timeZone: tz
        )
        
        let rtQuote = await realtimeQuoteTask
        let intradayResult = await intradayTask
        let periodResult = await periodTask
        
        let klineBars = periodResult?.bars ?? []
        let intradayBars = intradayResult?.bars ?? []
        
        let lastPrice = rtQuote?.lastPrice
            ?? intradayBars.last?.close
            ?? periodResult?.lastPrice
            ?? klineBars.last?.close
            ?? 0
        let previousClose = rtQuote?.previousClose
            ?? intradayResult?.previousClose
            ?? periodResult?.previousClose
            ?? (klineBars.count >= 2 ? klineBars[klineBars.count - 2].close : lastPrice)
        let dayOpen = rtQuote?.dayOpen
            ?? periodResult?.dayOpen
            ?? intradayBars.first?.open
            ?? klineBars.last?.open
            ?? lastPrice
        let high = rtQuote?.high
            ?? periodResult?.high
            ?? intradayBars.map(\.high).max()
            ?? klineBars.last?.high
            ?? lastPrice
        let low = rtQuote?.low
            ?? periodResult?.low
            ?? intradayBars.map(\.low).min()
            ?? klineBars.last?.low
            ?? lastPrice
        let volume = rtQuote?.volume
            ?? klineBars.last?.volume
            ?? intradayBars.reduce(0) { $0 + $1.volume }
        
        var barsByPeriod: [MarketChartPeriod: [MarketBar]] = [:]
        if !intradayBars.isEmpty {
            barsByPeriod[.intraday] = intradayBars
        }
        if !klineBars.isEmpty {
            barsByPeriod[period == .intraday ? .day : period] = klineBars
        }
        
        guard !barsByPeriod.isEmpty || lastPrice > 0 else {
            throw URLError(.cannotParseResponse)
        }
        
        return MarketQuoteSnapshot(
            instrument: MarketInstrument(
                namespace: instrument.namespace,
                symbol: instrument.symbol,
                name: instrument.name,
                eastmoneySecID: instrument.eastmoneySecID,
                tencentCode: resolvedTencent
            ),
            lastPrice: lastPrice,
            previousClose: previousClose > 0 ? previousClose : lastPrice,
            dayOpen: dayOpen > 0 ? dayOpen : lastPrice,
            high: high > 0 ? high : lastPrice,
            low: low > 0 ? low : lastPrice,
            volume: volume,
            barsByPeriod: barsByPeriod,
            updatedAt: Date(),
            turnoverRate: rtQuote?.turnoverRate,
            amount: rtQuote?.amount,
            peRatio: rtQuote?.peRatio,
            marketCap: rtQuote?.marketCap
        )
    }
    
    
    // MARK: - Provider Cascades
    
    private struct SeriesFetchResult {
        let bars: [MarketBar]
        let lastPrice: Double?
        let previousClose: Double?
        let dayOpen: Double?
        let high: Double?
        let low: Double?
    }
    
    
    private func fetchRealtimeQuoteWithFallback(
        instrument: MarketInstrument,
        tencentCode: String
    ) async -> ParsedRealtimeQuote? {
        if let tq = await self.fetchTencentRealtimeQuote(tencentCode: tencentCode) {
            return tq
        }
        if instrument.market == .aShare {
            return await self.fetchSinaRealtimeQuote(sinaCode: instrument.tencentCode)
        }
        return nil
    }
    
    
    private func fetchIntradayBars(
        instrument: MarketInstrument,
        tencentCode: String,
        timeZone: TimeZone
    ) async -> SeriesFetchResult? {
        // Primary: Eastmoney Push2His 1-minute klines (reliable for CN A-shares & HK stocks)
        if instrument.market != .unitedStates,
           let em = await self.fetchEastMoneyKLine(secID: instrument.eastmoneySecID, period: .intraday, count: 260, timeZone: timeZone),
           !em.bars.isEmpty
        {
            return em
        }
        
        // Secondary for A-shares: Sina 5-minute intraday slice, then flashdata fallback
        if instrument.market == .aShare {
            let sina = await self.fetchSinaKLine(sinaCode: instrument.tencentCode, period: .fiveMin, count: 48, timeZone: timeZone)
            if !sina.isEmpty {
                return SeriesFetchResult(bars: sina, lastPrice: nil, previousClose: nil, dayOpen: nil, high: nil, low: nil)
            }
            if let minuteBars = await self.fetchTencentFlashdataMinute(tencentCode: tencentCode, timeZone: timeZone),
               !minuteBars.isEmpty
            {
                return SeriesFetchResult(bars: minuteBars, lastPrice: nil, previousClose: nil, dayOpen: nil, high: nil, low: nil)
            }
        }
        return nil
    }
    
    
    private func fetchSeriesBars(
        instrument: MarketInstrument,
        tencentCode: String,
        period: MarketChartPeriod,
        timeZone: TimeZone
    ) async -> SeriesFetchResult? {
        if period == .fiveMin {
            if instrument.market != .unitedStates,
               let em5 = await self.fetchEastMoneyKLine(secID: instrument.eastmoneySecID, period: .fiveMin, count: 140, timeZone: timeZone),
               !em5.bars.isEmpty
            {
                return em5
            }
            if instrument.market == .aShare {
                let sina5 = await self.fetchSinaKLine(sinaCode: instrument.tencentCode, period: .fiveMin, count: 120, timeZone: timeZone)
                if !sina5.isEmpty {
                    return SeriesFetchResult(bars: sina5, lastPrice: nil, previousClose: nil, dayOpen: nil, high: nil, low: nil)
                }
            }
            // Fallback for US/unsupported 5m: provide recent daily bars rather than empty
            return try? await self.fetchTencentKLine(tencentCode: tencentCode, period: .day, count: 120, timeZone: timeZone)
        }
        
        // Daily / Weekly / Monthly cascade: Eastmoney Push2His -> Tencent fqkline -> Sina KLine
        if instrument.market == .aShare,
           let em = await self.fetchEastMoneyKLine(secID: instrument.eastmoneySecID, period: period, count: 180, timeZone: timeZone),
           !em.bars.isEmpty
        {
            return em
        }
        
        if let tq = try? await self.fetchTencentKLine(tencentCode: tencentCode, period: period, count: 180, timeZone: timeZone),
           !tq.bars.isEmpty
        {
            return tq
        }
        
        if instrument.market != .unitedStates,
           let em = await self.fetchEastMoneyKLine(secID: instrument.eastmoneySecID, period: period, count: 180, timeZone: timeZone),
           !em.bars.isEmpty
        {
            return em
        }
        
        if instrument.market == .aShare && period == .day {
            let sina = await self.fetchSinaKLine(sinaCode: instrument.tencentCode, period: .day, count: 180, timeZone: timeZone)
            if !sina.isEmpty {
                return SeriesFetchResult(bars: sina, lastPrice: nil, previousClose: nil, dayOpen: nil, high: nil, low: nil)
            }
        }
        return nil
    }
    
    
    // MARK: - HTTP Fetchers
    
    private func fetchTencentRealtimeQuote(tencentCode: String) async -> ParsedRealtimeQuote? {
        guard let url = URL(string: "https://qt.gtimg.cn/q=\(tencentCode)") else { return nil }
        guard let data = try? await self.request(url, referer: "https://gu.qq.com/"),
              let body = Self.decodeGBKString(from: data) ?? String(data: data, encoding: .utf8)
        else { return nil }
        return Self.parseTencentQuoteResponse(body)
    }
    
    
    private func fetchSinaRealtimeQuote(sinaCode: String) async -> ParsedRealtimeQuote? {
        guard let url = URL(string: "https://hq.sinajs.cn/list=\(sinaCode)") else { return nil }
        guard let data = try? await self.request(url, referer: "https://finance.sina.com.cn/"),
              let body = Self.decodeGBKString(from: data) ?? String(data: data, encoding: .utf8)
        else { return nil }
        return Self.parseSinaQuoteResponse(body)
    }
    
    
    private func fetchEastMoneyKLine(
        secID: String,
        period: MarketChartPeriod,
        count: Int,
        timeZone: TimeZone
    ) async -> SeriesFetchResult? {
        let klt: String = switch period {
            case .intraday: "1"
            case .fiveMin: "5"
            case .day: "101"
            case .week: "102"
            case .month: "103"
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "push2his.eastmoney.com"
        components.path = "/api/qt/stock/kline/get"
        components.queryItems = [
            URLQueryItem(name: "secid", value: secID),
            URLQueryItem(name: "fields1", value: "f1,f2,f3,f4,f5,f6"),
            URLQueryItem(name: "fields2", value: "f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61"),
            URLQueryItem(name: "klt", value: klt),
            URLQueryItem(name: "fqt", value: "1"),
            URLQueryItem(name: "end", value: "20500101"),
            URLQueryItem(name: "lmt", value: "\(count)"),
        ]
        guard let url = components.url,
              let data = try? await self.request(url, referer: "https://quote.eastmoney.com/"),
              let parsed = Self.parseEastMoneyKlinePayload(data, period: period, timeZone: timeZone)
        else { return nil }
        return SeriesFetchResult(
            bars: parsed.bars,
            lastPrice: parsed.bars.last?.close,
            previousClose: parsed.previousClose,
            dayOpen: nil,
            high: nil,
            low: nil
        )
    }
    
    
    private func fetchTencentKLine(
        tencentCode: String,
        period: MarketChartPeriod,
        count: Int,
        timeZone: TimeZone
    ) async throws -> SeriesFetchResult {
        let kType: String = switch period {
            case .intraday, .fiveMin, .day: "day"
            case .week: "week"
            case .month: "month"
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "web.ifzq.gtimg.cn"
        components.path = "/appstock/app/fqkline/get"
        components.queryItems = [
            URLQueryItem(name: "param", value: "\(tencentCode),\(kType),,,\(count),qfq"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        
        let data = try await self.request(url, referer: "https://gu.qq.com/")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = root["code"] as? Int, code == 0,
              let dataDict = root["data"] as? [String: Any],
              let payload = (dataDict[tencentCode] as? [String: Any]) ?? dataDict.values.first as? [String: Any]
        else { throw URLError(.cannotParseResponse) }
        
        let rawRows = (payload["qfq\(kType)"] as? [[Any]])
            ?? (payload[kType] as? [[Any]])
            ?? []
        
        let bars: [MarketBar] = rawRows.compactMap { row in
            guard row.count >= 5,
                  let label = row[0] as? String,
                  let open = Self.doubleValue(row[1]),
                  let close = Self.doubleValue(row[2]),
                  let high = Self.doubleValue(row[3]),
                  let low = Self.doubleValue(row[4]),
                  [open, close, high, low].allSatisfy({ $0.isFinite && $0 > 0 })
            else { return nil }
            let volume = row.count >= 6 ? (Self.doubleValue(row[5]) ?? 0) : 0
            return MarketBar(
                timeLabel: label,
                date: Self.parseBarDate(label, timeZone: timeZone),
                open: open,
                close: close,
                high: max(open, close, high, low),
                low: min(open, close, high, low),
                volume: max(0, volume)
            )
        }
        
        var qtLast: Double?
        var qtPrevClose: Double?
        var qtOpen: Double?
        var qtHigh: Double?
        var qtLow: Double?
        if let qt = payload["qt"] as? [String: Any],
           let fields = (qt[tencentCode] as? [Any]) ?? (qt.values.first as? [Any])
        {
            qtLast = Self.doubleValue(fields[safe: 3])
            qtPrevClose = Self.doubleValue(fields[safe: 4])
            qtOpen = Self.doubleValue(fields[safe: 5])
            qtHigh = Self.doubleValue(fields[safe: 33])
            qtLow = Self.doubleValue(fields[safe: 34])
        }
        
        return SeriesFetchResult(
            bars: bars,
            lastPrice: qtLast,
            previousClose: qtPrevClose,
            dayOpen: qtOpen,
            high: qtHigh,
            low: qtLow
        )
    }
    
    
    private func fetchTencentFlashdataMinute(tencentCode: String, timeZone: TimeZone) async -> [MarketBar]? {
        guard let url = URL(string: "https://data.gtimg.cn/flashdata/hushen/minute/\(tencentCode).js"),
              let data = try? await self.request(url, referer: "https://gu.qq.com/"),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        
        var rawDate = ""
        var prevCumVol: Double = 0
        var bars: [MarketBar] = []
        let calendar = Calendar(identifier: .gregorian)
        var compsBase: DateComponents?
        
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("date:") {
                let token = line.replacingOccurrences(of: "date:", with: "").replacingOccurrences(of: "\\n\\", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if token.count == 6,
                   let yy = Int(token.prefix(2)),
                   let mm = Int(token.dropFirst(2).prefix(2)),
                   let dd = Int(token.dropFirst(4).prefix(2))
                {
                    rawDate = String(format: "20%02d-%02d-%02d", yy, mm, dd)
                    compsBase = DateComponents(timeZone: timeZone, year: 2000 + yy, month: mm, day: dd)
                }
                continue
            }
            let cleaned = line.replacingOccurrences(of: "\\n\\", with: "").replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = cleaned.split(separator: " ")
            guard parts.count >= 3,
                  parts[0].count == 4,
                  let price = Double(parts[1]), price > 0,
                  let cumVol = Double(parts[2])
            else { continue }
            
            let hhmm = parts[0]
            let label = "\(hhmm.prefix(2)):\(hhmm.suffix(2))"
            var barDate: Date?
            if var base = compsBase, let h = Int(hhmm.prefix(2)), let m = Int(hhmm.suffix(2)) {
                base.hour = h
                base.minute = m
                barDate = calendar.date(from: base)
            }
            let stepVol = max(0, cumVol - prevCumVol)
            prevCumVol = max(prevCumVol, cumVol)
            bars.append(MarketBar(
                timeLabel: rawDate.isEmpty ? label : "\(rawDate) \(label)",
                date: barDate,
                open: price,
                close: price,
                high: price,
                low: price,
                volume: stepVol
            ))
        }
        return bars.isEmpty ? nil : bars
    }
    
    
    private func fetchSinaKLine(
        sinaCode: String,
        period: MarketChartPeriod,
        count: Int,
        timeZone: TimeZone
    ) async -> [MarketBar] {
        let scale = (period == .fiveMin || period == .intraday) ? "5" : "240"
        var components = URLComponents()
        components.scheme = "https"
        components.host = "quotes.sina.cn"
        components.path = "/cn/api/json_v2.php/CN_MarketDataService.getKLineData"
        components.queryItems = [
            URLQueryItem(name: "symbol", value: sinaCode),
            URLQueryItem(name: "scale", value: scale),
            URLQueryItem(name: "ma", value: "no"),
            URLQueryItem(name: "datalen", value: "\(count)"),
        ]
        guard let url = components.url,
              let data = try? await self.request(url, referer: "https://finance.sina.com.cn/")
        else { return [] }
        return Self.parseSinaKlineJSON(data, period: period, timeZone: timeZone)
    }
    
    
    private func searchTencentSmartbox(query: String) async -> [MarketInstrument] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "smartbox.gtimg.cn"
        components.path = "/s3/"
        components.queryItems = [
            URLQueryItem(name: "v", value: "2"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "t", value: "all"),
            URLQueryItem(name: "c", value: "10"),
        ]
        guard let url = components.url,
              let data = try? await self.request(url, referer: "https://gu.qq.com/"),
              let body = String(data: data, encoding: .utf8),
              let firstQuote = body.firstIndex(of: "\""),
              let lastQuote = body.lastIndex(of: "\""),
              firstQuote < lastQuote
        else { return [] }
        
        let rawPayload = String(body[body.index(after: firstQuote)..<lastQuote])
        return rawPayload.split(separator: "^").compactMap { entry -> MarketInstrument? in
            let parts = entry.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3 else { return nil }
            let marketTag = parts[0].lowercased()
            let code = parts[1]
            let name = Self.decodeUnicodeEscapes(parts[2])
            let ns: MarketNamespace? = switch marketTag {
                case "sh": .shanghai
                case "sz": .shenzhen
                case "bj": .beijing
                case "hk": .hongKong
                case "us": .unitedStates
                default: nil
            }
            guard let ns else { return nil }
            let symbol = ns == .unitedStates ? (code.split(separator: ".").first.map(String.init) ?? code) : code
            return MarketInstrument(
                namespace: ns,
                symbol: symbol,
                name: name,
                tencentCode: ns == .unitedStates ? "us\(code.uppercased())" : "\(ns.rawValue)\(symbol)"
            )
        }
    }
    
    
    // MARK: - US Tencent Exchange Suffix Resolver (`smartbox.gtimg.cn`)
    
    private func resolvedTencentCode(for instrument: MarketInstrument) async throws -> String {
        guard instrument.namespace == .unitedStates else {
            return instrument.tencentCode
        }
        if instrument.tencentCode.contains(".") {
            return instrument.tencentCode
        }
        if let cached = self.usTencentSuffixCache[instrument.symbol] {
            return cached
        }
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "smartbox.gtimg.cn"
        components.path = "/s3/"
        components.queryItems = [
            URLQueryItem(name: "v", value: "2"),
            URLQueryItem(name: "q", value: instrument.symbol),
            URLQueryItem(name: "t", value: "all"),
            URLQueryItem(name: "c", value: "1"),
        ]
        if let url = components.url,
           let data = try? await self.request(url, referer: "https://gu.qq.com/"),
           let body = String(data: data, encoding: .utf8)
        {
            let pattern = #"us~([A-Za-z0-9\.\-]+)~"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length)),
               match.numberOfRanges >= 2
            {
                let token = (body as NSString).substring(with: match.range(at: 1))
                let parts = token.split(separator: ".")
                if parts.count == 2, parts[0].uppercased() == instrument.symbol.uppercased() {
                    let resolved = "us\(parts[0].uppercased()).\(parts[1].uppercased())"
                    self.usTencentSuffixCache[instrument.symbol] = resolved
                    return resolved
                }
            }
        }
        let fallback = "us\(instrument.symbol).OQ"
        self.usTencentSuffixCache[instrument.symbol] = fallback
        return fallback
    }
    
    
    // MARK: - Pure Parsers (Test-Verified Offline)
    
    nonisolated static func decodeGBKString(from data: Data) -> String? {
        let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        return String(data: data, encoding: nsEncoding)
    }
    
    
    nonisolated static func parseTencentQuoteResponse(_ body: String) -> ParsedRealtimeQuote? {
        guard let firstQuote = body.firstIndex(of: "\""),
              let lastQuote = body.lastIndex(of: "\""),
              firstQuote < lastQuote
        else { return nil }
        let inner = String(body[body.index(after: firstQuote)..<lastQuote])
        let fields = inner.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        guard fields.count > 6,
              let lastPrice = Double(fields[3]), lastPrice.isFinite, lastPrice > 0,
              let prevClose = Double(fields[4]), prevClose.isFinite, prevClose > 0
        else { return nil }
        
        let dayOpen = Double(fields[5]).flatMap { $0 > 0 ? $0 : nil } ?? lastPrice
        let volume = Double(fields[6]) ?? 0
        let high = Self.positiveDouble(fields[safe: 33]) ?? Self.positiveDouble(fields[safe: 41]) ?? max(dayOpen, lastPrice)
        let low = Self.positiveDouble(fields[safe: 34]) ?? Self.positiveDouble(fields[safe: 42]) ?? min(dayOpen, lastPrice)
        let amount = Self.positiveDouble(fields[safe: 37])
        let turnoverRate = Self.positiveDouble(fields[safe: 38])
        let peRatio = (fields[safe: 39].flatMap(Double.init)).flatMap { ($0.isFinite && $0 != 0) ? $0 : nil }
        let marketCap = Self.positiveDouble(fields[safe: 45])
        
        return ParsedRealtimeQuote(
            lastPrice: lastPrice,
            previousClose: prevClose,
            dayOpen: dayOpen,
            high: max(high, lastPrice),
            low: min(low, lastPrice),
            volume: max(0, volume),
            amount: amount,
            turnoverRate: turnoverRate,
            peRatio: peRatio,
            marketCap: marketCap
        )
    }
    
    
    nonisolated static func parseSinaQuoteResponse(_ body: String) -> ParsedRealtimeQuote? {
        guard let firstQuote = body.firstIndex(of: "\""),
              let lastQuote = body.lastIndex(of: "\""),
              firstQuote < lastQuote
        else { return nil }
        let inner = String(body[body.index(after: firstQuote)..<lastQuote])
        let fields = inner.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 10,
              let open = Double(fields[1]),
              let prevClose = Double(fields[2]), prevClose > 0,
              let lastPrice = Double(fields[3]), lastPrice > 0,
              let high = Double(fields[4]),
              let low = Double(fields[5])
        else { return nil }
        
        let rawVolShares = Double(fields[8]) ?? 0
        let rawAmountYuan = Double(fields[9]) ?? 0
        return ParsedRealtimeQuote(
            lastPrice: lastPrice,
            previousClose: prevClose,
            dayOpen: open > 0 ? open : lastPrice,
            high: high > 0 ? max(high, lastPrice) : lastPrice,
            low: low > 0 ? min(low, lastPrice) : lastPrice,
            volume: rawVolShares / 100.0,
            amount: rawAmountYuan > 0 ? (rawAmountYuan / 10_000.0) : nil,
            turnoverRate: nil,
            peRatio: nil,
            marketCap: nil
        )
    }
    
    
    nonisolated static func parseEastMoneyKlinePayload(
        _ data: Data,
        period: MarketChartPeriod,
        timeZone: TimeZone
    ) -> (bars: [MarketBar], previousClose: Double?)? {
        guard let envelope = try? JSONDecoder().decode(EastMoneyKlineEnvelope.self, from: data),
              envelope.rc == 0,
              let payload = envelope.data,
              let klines = payload.klines,
              !klines.isEmpty
        else { return nil }
        
        let latestTradingDay = klines.last.map { String($0.prefix(10)) }
        var bars: [MarketBar] = []
        bars.reserveCapacity(klines.count)
        
        for line in klines {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 6,
                  let open = Double(cols[1]),
                  let close = Double(cols[2]),
                  let high = Double(cols[3]),
                  let low = Double(cols[4]),
                  [open, close, high, low].allSatisfy({ $0.isFinite && $0 > 0 })
            else { continue }
            
            let timestampRaw = cols[0]
            if period == .intraday, let latestTradingDay, !timestampRaw.hasPrefix(latestTradingDay) {
                continue
            }
            let volume = max(0, Double(cols[5]) ?? 0)
            let displayLabel: String = if period == .intraday, timestampRaw.count >= 16 {
                String(timestampRaw.suffix(5))
            } else {
                timestampRaw
            }
            bars.append(MarketBar(
                timeLabel: displayLabel,
                date: Self.parseBarDate(timestampRaw, timeZone: timeZone),
                open: open,
                close: close,
                high: max(open, close, high, low),
                low: min(open, close, high, low),
                volume: volume
            ))
        }
        guard !bars.isEmpty else { return nil }
        let prevClose = payload.preKPrice.flatMap { ($0.isFinite && $0 > 0) ? $0 : nil }
        return (bars, prevClose)
    }
    
    
    nonisolated static func parseSinaKlineJSON(
        _ data: Data,
        period: MarketChartPeriod,
        timeZone: TimeZone
    ) -> [MarketBar] {
        guard let rows = try? JSONDecoder().decode([SinaKlineDTO].self, from: data) else { return [] }
        return rows.compactMap { row in
            guard let open = Double(row.open),
                  let high = Double(row.high),
                  let low = Double(row.low),
                  let close = Double(row.close),
                  [open, high, low, close].allSatisfy({ $0.isFinite && $0 > 0 })
            else { return nil }
            let volume = max(0, Double(row.volume) ?? 0)
            let cleanLabel = row.day.hasSuffix(":00") && row.day.count == 19
                ? String(row.day.dropLast(3))
                : row.day
            let label = (period == .intraday && cleanLabel.count >= 5) ? String(cleanLabel.suffix(5)) : cleanLabel
            return MarketBar(
                timeLabel: label,
                date: Self.parseBarDate(row.day, timeZone: timeZone),
                open: open,
                close: close,
                high: max(open, close, high, low),
                low: min(open, close, high, low),
                volume: volume
            )
        }
    }
    
    
    nonisolated static func parseBarDate(_ raw: String, timeZone: TimeZone) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: " ")
        let dateParts = parts[0].split(separator: "-")
        guard dateParts.count == 3,
              let year = Int(dateParts[0]),
              let month = Int(dateParts[1]),
              let day = Int(dateParts[2])
        else { return nil }
        
        var comps = DateComponents()
        comps.timeZone = timeZone
        comps.year = year
        comps.month = month
        comps.day = day
        
        if parts.count >= 2 {
            let timeParts = parts[1].split(separator: ":")
            if timeParts.count >= 2,
               let hour = Int(timeParts[0]),
               let minute = Int(timeParts[1])
            {
                comps.hour = hour
                comps.minute = minute
                if timeParts.count >= 3, let second = Int(timeParts[2]) {
                    comps.second = second
                }
            }
        } else {
            comps.hour = 15
            comps.minute = 0
        }
        return Calendar(identifier: .gregorian).date(from: comps)
    }
    
    
    // MARK: - Helpers
    
    private func request(_ url: URL, referer: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        req.setValue(referer, forHTTPHeaderField: "Referer")
        let (data, response) = try await self.session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
    
    
    private static func instrument(from item: EastMoneySuggestItem) -> MarketInstrument? {
        let classify = item.classify.lowercased()
        let jys = item.jys.uppercased()
        let namespace: MarketNamespace? = switch item.mktNum {
            case "1":
                ["astock", "index", "fund", "bond"].contains(classify) ? .shanghai : nil
            case "0":
                if ["astock", "index", "fund", "neeq"].contains(classify) {
                    (classify == "neeq" || item.code.hasPrefix("4") || item.code.hasPrefix("8") || item.code.hasPrefix("9"))
                        ? .beijing
                        : .shenzhen
                } else {
                    nil
                }
            case "116":
                classify == "hk" ? .hongKong : nil
            case "124", "100":
                (jys == "HS" || item.code.upperCaseContainsHKIndex || classify == "universalindex") ? .hongKong : nil
            case "105", "106", "107":
                ["usstock", "usindex", "fund"].contains(classify) ? .unitedStates : nil
            default:
                nil
        }
        guard let namespace else { return nil }
        let tencentCode: String? = switch namespace {
            case .hongKong where !item.code.allSatisfy(\.isNumber):
                "hk\(item.code.uppercased())"
            default:
                nil
        }
        return MarketInstrument(
            namespace: namespace,
            symbol: item.code,
            name: item.name,
            eastmoneySecID: item.quoteID,
            tencentCode: tencentCode
        )
    }
    
    
    private nonisolated static func decodeUnicodeEscapes(_ raw: String) -> String {
        guard raw.contains("\\u") else { return raw }
        let quoted = "\"" + raw.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        if let data = quoted.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data)
        {
            return decoded
        }
        return raw
    }
    
    
    private nonisolated static func positiveDouble(_ raw: String?) -> Double? {
        guard let raw, let val = Double(raw), val.isFinite, val > 0 else { return nil }
        return val
    }
    
    
    private static func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }
}


private extension String {
    var upperCaseContainsHKIndex: Bool {
        let u = self.uppercased()
        return u == "HSTECH" || u == "HSI" || u == "HSCEI"
    }
}


private extension Array {
    subscript(safe index: Int) -> Element? {
        self.indices.contains(index) ? self[index] : nil
    }
}


// MARK: - Provider DTOs

private struct EastMoneySuggestEnvelope: Decodable {
    let table: EastMoneySuggestTable
    
    enum CodingKeys: String, CodingKey {
        case table = "QuotationCodeTable"
    }
}


private struct EastMoneySuggestTable: Decodable {
    let data: [EastMoneySuggestItem]
    
    enum CodingKeys: String, CodingKey {
        case data = "Data"
    }
}


private struct EastMoneySuggestItem: Decodable {
    let code: String
    let name: String
    let classify: String
    let jys: String
    let mktNum: String
    let quoteID: String
    
    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case name = "Name"
        case classify = "Classify"
        case jys = "JYS"
        case mktNum = "MktNum"
        case quoteID = "QuoteID"
    }
    
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.classify = try c.decodeIfPresent(String.self, forKey: .classify) ?? ""
        self.jys = try c.decodeIfPresent(String.self, forKey: .jys) ?? ""
        self.mktNum = try c.decodeIfPresent(String.self, forKey: .mktNum) ?? ""
        self.quoteID = try c.decodeIfPresent(String.self, forKey: .quoteID) ?? ""
    }
}


private struct EastMoneyKlineEnvelope: Decodable {
    let rc: Int
    let data: EastMoneyKlinePayload?
}


private struct EastMoneyKlinePayload: Decodable {
    let preKPrice: Double?
    let klines: [String]?
}


private struct SinaKlineDTO: Decodable {
    let day: String
    let open: String
    let high: String
    let low: String
    let close: String
    let volume: String
}
