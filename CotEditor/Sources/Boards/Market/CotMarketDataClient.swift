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

/// Live public market data client fetching Eastmoney security search + intraday 1-min trends
/// and Tencent `fqkline/get` daily/weekly/monthly K-lines with zero external dependencies.
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
            config.timeoutIntervalForRequest = 12
            config.timeoutIntervalForResource = 18
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }
    
    
    // MARK: - Search (Eastmoney Suggest + Local Alias Priority)
    
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
        guard let url = components.url else { return results }
        
        let data = try await self.request(url, referer: "https://quote.eastmoney.com/")
        let envelope = try JSONDecoder().decode(EastMoneySuggestEnvelope.self, from: data)
        for item in envelope.table.data {
            guard let parsed = Self.instrument(from: item) else { continue }
            if seen.insert(parsed.instrumentID).inserted {
                results.append(parsed)
            }
        }
        return results
    }
    
    
    // MARK: - K-Line & Intraday Snapshot
    
    func fetchQuoteAndBars(
        for instrument: MarketInstrument,
        period: MarketChartPeriod
    ) async throws -> MarketQuoteSnapshot {
        let resolvedTencent = try await self.resolvedTencentCode(for: instrument)
        
        async let klineFetch = self.fetchTencentKLine(
            tencentCode: resolvedTencent,
            period: period == .intraday ? .day : period,
            count: 90
        )
        async let intradayFetch = self.fetchEastMoneyIntraday(secID: instrument.eastmoneySecID)
        
        let klineResult = try? await klineFetch
        let intradayResult = try? await intradayFetch
        
        let klineBars = klineResult?.bars ?? []
        let intradayBars = intradayResult?.bars ?? []
        
        let lastPrice = intradayBars.last?.close
            ?? klineResult?.lastPrice
            ?? klineBars.last?.close
            ?? 0
        let previousClose = intradayResult?.previousClose
            ?? klineResult?.previousClose
            ?? (klineBars.count >= 2 ? klineBars[klineBars.count - 2].close : lastPrice)
        let dayOpen = klineResult?.dayOpen
            ?? intradayBars.first?.open
            ?? klineBars.last?.open
            ?? lastPrice
        let high = klineResult?.high
            ?? intradayBars.map(\.high).max()
            ?? klineBars.last?.high
            ?? lastPrice
        let low = klineResult?.low
            ?? intradayBars.map(\.low).min()
            ?? klineBars.last?.low
            ?? lastPrice
        let volume = klineBars.last?.volume
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
            updatedAt: Date()
        )
    }
    
    
    // MARK: - Tencent K-Line (`day` / `week` / `month`)
    
    private struct TencentKLineResponse {
        let bars: [MarketBar]
        let lastPrice: Double?
        let previousClose: Double?
        let dayOpen: Double?
        let high: Double?
        let low: Double?
    }
    
    
    private func fetchTencentKLine(
        tencentCode: String,
        period: MarketChartPeriod,
        count: Int
    ) async throws -> TencentKLineResponse {
        let kType: String = switch period {
            case .intraday, .day: "day"
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
                date: nil,
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
        
        return TencentKLineResponse(
            bars: bars,
            lastPrice: qtLast,
            previousClose: qtPrevClose,
            dayOpen: qtOpen,
            high: qtHigh,
            low: qtLow
        )
    }
    
    
    // MARK: - Eastmoney 1-Minute Intraday (`trends2/get`)
    
    private func fetchEastMoneyIntraday(secID: String) async throws -> (bars: [MarketBar], previousClose: Double)? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "push2delay.eastmoney.com"
        components.path = "/api/qt/stock/trends2/get"
        components.queryItems = [
            URLQueryItem(name: "secid", value: secID),
            URLQueryItem(name: "fields1", value: "f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13"),
            URLQueryItem(name: "fields2", value: "f51,f52,f53,f54,f55,f56,f57,f58"),
            URLQueryItem(name: "iscr", value: "0"),
            URLQueryItem(name: "ndays", value: "1"),
        ]
        guard let url = components.url else { return nil }
        
        let data = try await self.request(url, referer: "https://quote.eastmoney.com/")
        let envelope = try JSONDecoder().decode(EastMoneyTrendsEnvelope.self, from: data)
        guard envelope.rc == 0, let payload = envelope.data else { return nil }
        
        let bars: [MarketBar] = payload.trends.compactMap { line in
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cols.count >= 6,
                  let open = Double(cols[1]),
                  let close = Double(cols[2]),
                  let high = Double(cols[3]),
                  let low = Double(cols[4]),
                  [open, close, high, low].allSatisfy({ $0.isFinite && $0 > 0 })
            else { return nil }
            let volume = Double(cols[5]) ?? 0
            let fullTime = String(cols[0])
            let shortTime = fullTime.count >= 5 ? String(fullTime.suffix(5)) : fullTime
            return MarketBar(
                timeLabel: shortTime,
                date: nil,
                open: open,
                close: close,
                high: max(open, close, high, low),
                low: min(open, close, high, low),
                volume: max(0, volume)
            )
        }
        guard !bars.isEmpty else { return nil }
        return (bars, payload.preClose)
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
            // Example: v_hint="us~aapl.oq~苹果~pg~GP^..."
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
    
    
    // MARK: - Helpers
    
    private func request(_ url: URL, referer: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
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


private struct EastMoneyTrendsEnvelope: Decodable {
    let rc: Int
    let data: EastMoneyTrendsPayload?
}


private struct EastMoneyTrendsPayload: Decodable {
    let preClose: Double
    let trends: [String]
}
