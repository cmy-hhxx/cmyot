//
//  CotMarketModels.swift
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
import SwiftUI

/// Exchange namespace identifying security ownership independent of quote provider.
nonisolated enum MarketNamespace: String, Codable, CaseIterable, Sendable {
    
    case shanghai = "sh"
    case shenzhen = "sz"
    case beijing = "bj"
    case hongKong = "hk"
    case unitedStates = "us"
    
    var market: MarketRegion {
        switch self {
            case .shanghai, .shenzhen, .beijing: .aShare
            case .hongKong: .hongKong
            case .unitedStates: .unitedStates
        }
    }
    
    var displayName: String {
        switch self {
            case .shanghai: "SH"
            case .shenzhen: "SZ"
            case .beijing: "BJ"
            case .hongKong: "HK"
            case .unitedStates: "US"
        }
    }
    
    func normalizeSymbol(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
            case .hongKong:
                if clean.allSatisfy(\.isNumber), clean.count < 5 {
                    return String(repeating: "0", count: 5 - clean.count) + clean
                }
                return clean.uppercased()
            case .unitedStates:
                return clean.uppercased()
            case .shanghai, .shenzhen, .beijing:
                return clean
        }
    }
}


/// Market region carrying price-direction color conventions (CN/HK red-up vs US green-up).
nonisolated enum MarketRegion: String, Codable, Sendable {
    
    case aShare
    case hongKong
    case unitedStates
    
    var usesRedUpGreenDown: Bool {
        self != .unitedStates
    }
    
    var timeZone: TimeZone {
        switch self {
            case .aShare: TimeZone(identifier: "Asia/Shanghai")!
            case .hongKong: TimeZone(identifier: "Asia/Hong_Kong")!
            case .unitedStates: TimeZone(identifier: "America/New_York")!
        }
    }
    
    var currencyPrefix: String {
        switch self {
            case .aShare: "¥"
            case .hongKong: "HK$"
            case .unitedStates: "$"
        }
    }
}


/// Resolved instrument candidate returned by search or alias lookup.
nonisolated struct MarketInstrument: Identifiable, Codable, Hashable, Sendable {
    
    let instrumentID: String
    let namespace: MarketNamespace
    let symbol: String
    let name: String
    let eastmoneySecID: String
    let tencentCode: String
    
    var id: String { self.instrumentID }
    var market: MarketRegion { self.namespace.market }
    
    
    init(
        namespace: MarketNamespace,
        symbol: String,
        name: String,
        eastmoneySecID: String? = nil,
        tencentCode: String? = nil
    ) {
        let normalized = namespace.normalizeSymbol(symbol)
        self.instrumentID = "\(namespace.rawValue):\(normalized)"
        self.namespace = namespace
        self.symbol = normalized
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let eastmoneySecID, !eastmoneySecID.isEmpty {
            self.eastmoneySecID = eastmoneySecID
        } else {
            self.eastmoneySecID = switch namespace {
                case .shanghai: "1.\(normalized)"
                case .shenzhen, .beijing: "0.\(normalized)"
                case .hongKong: normalized.allSatisfy(\.isNumber) ? "116.\(normalized)" : "124.\(normalized)"
                case .unitedStates: "105.\(normalized)"
            }
        }
        
        if let tencentCode, !tencentCode.isEmpty {
            self.tencentCode = tencentCode
        } else {
            self.tencentCode = switch namespace {
                case .shanghai: "sh\(normalized)"
                case .shenzhen: "sz\(normalized)"
                case .beijing: "bj\(normalized)"
                case .hongKong: "hk\(normalized)"
                case .unitedStates: "us\(normalized)"
            }
        }
    }
    
    
    init(record: WatchlistStockRecord) {
        let ns = MarketNamespace(rawValue: record.namespace) ?? .hongKong
        self.init(
            namespace: ns,
            symbol: record.symbol,
            name: record.name,
            eastmoneySecID: record.eastmoneySecID,
            tencentCode: record.tencentCode
        )
    }
    
    
    func toRecord(sortOrder: Int = 0, thesisNote: String = "", addedBy: String = "user") -> WatchlistStockRecord {
        let now = Date()
        return WatchlistStockRecord(
            instrumentID: self.instrumentID,
            namespace: self.namespace.rawValue,
            symbol: self.symbol,
            name: self.name,
            eastmoneySecID: self.eastmoneySecID,
            tencentCode: self.tencentCode,
            sortOrder: sortOrder,
            thesisNote: thesisNote,
            alertUpPrice: nil,
            alertDownPrice: nil,
            lastPrice: nil,
            lastChangePct: nil,
            addedBy: addedBy,
            createdAt: now,
            updatedAt: now
        )
    }
}


/// Single OHLCV bar for K-line candlesticks or 1-minute intraday curves.
nonisolated struct MarketBar: Hashable, Sendable {
    
    let timeLabel: String
    let date: Date?
    let open: Double
    let close: Double
    let high: Double
    let low: Double
    let volume: Double
    
    var isRising: Bool { self.close >= self.open }
}


/// Complete live quote + K-line & intraday bar series for a single instrument.
nonisolated struct MarketQuoteSnapshot: Sendable, Equatable {
    
    let instrument: MarketInstrument
    let lastPrice: Double
    let previousClose: Double
    let dayOpen: Double
    let high: Double
    let low: Double
    let volume: Double
    let barsByPeriod: [MarketChartPeriod: [MarketBar]]
    let updatedAt: Date
    let turnoverRate: Double?
    let amount: Double?
    let peRatio: Double?
    let marketCap: Double?
    
    init(
        instrument: MarketInstrument,
        lastPrice: Double,
        previousClose: Double,
        dayOpen: Double,
        high: Double,
        low: Double,
        volume: Double,
        barsByPeriod: [MarketChartPeriod: [MarketBar]],
        updatedAt: Date,
        turnoverRate: Double? = nil,
        amount: Double? = nil,
        peRatio: Double? = nil,
        marketCap: Double? = nil
    ) {
        self.instrument = instrument
        self.lastPrice = lastPrice
        self.previousClose = previousClose
        self.dayOpen = dayOpen
        self.high = high
        self.low = low
        self.volume = volume
        self.barsByPeriod = barsByPeriod
        self.updatedAt = updatedAt
        self.turnoverRate = turnoverRate
        self.amount = amount
        self.peRatio = peRatio
        self.marketCap = marketCap
    }
    
    var changeAmount: Double { self.lastPrice - self.previousClose }
    
    var changePercent: Double {
        guard self.previousClose > 0 else { return 0 }
        return (self.lastPrice - self.previousClose) / self.previousClose * 100.0
    }
    
    var isRising: Bool { self.lastPrice >= self.previousClose }
    
    static func == (lhs: MarketQuoteSnapshot, rhs: MarketQuoteSnapshot) -> Bool {
        lhs.instrument == rhs.instrument
            && lhs.lastPrice == rhs.lastPrice
            && lhs.previousClose == rhs.previousClose
            && lhs.updatedAt == rhs.updatedAt
            && lhs.barsByPeriod.keys == rhs.barsByPeriod.keys
    }
}


/// Market direction colors adapted from MarketSprite for both light and dark Studio themes.
enum MarketTonePalette {
    
    static let upRed = Color(red: 0.92, green: 0.28, blue: 0.26)
    static let downGreen = Color(red: 0.14, green: 0.72, blue: 0.45)
    
    static func directionColor(isRising: Bool, market: MarketRegion) -> Color {
        if market.usesRedUpGreenDown {
            return isRising ? Self.upRed : Self.downGreen
        } else {
            return isRising ? Self.downGreen : Self.upRed
        }
    }
}


/// Zero-latency built-in alias catalog resolving flagship CN/HK/US symbols immediately.
nonisolated enum MarketAliasCatalog {
    
    private static let catalog: [(aliases: [String], instrument: MarketInstrument)] = [
        (["三安光电", "三安", "600703", "sh600703"], MarketInstrument(namespace: .shanghai, symbol: "600703", name: "三安光电", eastmoneySecID: "1.600703", tencentCode: "sh600703")),
        (["京东方", "京东方a", "京东方A", "000725", "sz000725"], MarketInstrument(namespace: .shenzhen, symbol: "000725", name: "京东方A", eastmoneySecID: "0.000725", tencentCode: "sz000725")),
        (["恒生科技", "恒生科技指数", "hstech", "恒科"], MarketInstrument(namespace: .hongKong, symbol: "HSTECH", name: "恒生科技指数", eastmoneySecID: "124.HSTECH", tencentCode: "hkHSTECH")),
        (["恒生指数", "恒指", "hsi"], MarketInstrument(namespace: .hongKong, symbol: "HSI", name: "恒生指数", eastmoneySecID: "100.HSI", tencentCode: "hkHSI")),
        (["恒生国企", "国企指数", "hscei"], MarketInstrument(namespace: .hongKong, symbol: "HSCEI", name: "恒生中国企业指数", eastmoneySecID: "100.HSCEI", tencentCode: "hkHSCEI")),
        (["上证指数", "上证", "大盘", "sh000001"], MarketInstrument(namespace: .shanghai, symbol: "000001", name: "上证指数", eastmoneySecID: "1.000001", tencentCode: "sh000001")),
        (["沪深300", "hs300"], MarketInstrument(namespace: .shanghai, symbol: "000300", name: "沪深300", eastmoneySecID: "1.000300", tencentCode: "sh000300")),
        (["恒生科技etf", "513180"], MarketInstrument(namespace: .shanghai, symbol: "513180", name: "恒生科技ETF华夏", eastmoneySecID: "1.513180", tencentCode: "sh513180")),
        (["腾讯", "腾讯控股", "00700", "700"], MarketInstrument(namespace: .hongKong, symbol: "00700", name: "腾讯控股", eastmoneySecID: "116.00700", tencentCode: "hk00700")),
        (["阿里巴巴", "阿里", "09988", "9988"], MarketInstrument(namespace: .hongKong, symbol: "09988", name: "阿里巴巴-W", eastmoneySecID: "116.09988", tencentCode: "hk09988")),
        (["美团", "03690", "3690"], MarketInstrument(namespace: .hongKong, symbol: "03690", name: "美团-W", eastmoneySecID: "116.03690", tencentCode: "hk03690")),
        (["小米", "小米集团", "01810", "1810"], MarketInstrument(namespace: .hongKong, symbol: "01810", name: "小米集团-W", eastmoneySecID: "116.01810", tencentCode: "hk01810")),
        (["贵州茅台", "茅台", "600519"], MarketInstrument(namespace: .shanghai, symbol: "600519", name: "贵州茅台", eastmoneySecID: "1.600519", tencentCode: "sh600519")),
        (["宁德时代", "宁王", "300750"], MarketInstrument(namespace: .shenzhen, symbol: "300750", name: "宁德时代", eastmoneySecID: "0.300750", tencentCode: "sz300750")),
        (["比亚迪", "002594"], MarketInstrument(namespace: .shenzhen, symbol: "002594", name: "比亚迪", eastmoneySecID: "0.002594", tencentCode: "sz002594")),
        (["英伟达", "nvda"], MarketInstrument(namespace: .unitedStates, symbol: "NVDA", name: "英伟达", eastmoneySecID: "105.NVDA", tencentCode: "usNVDA.OQ")),
        (["苹果", "aapl"], MarketInstrument(namespace: .unitedStates, symbol: "AAPL", name: "苹果", eastmoneySecID: "105.AAPL", tencentCode: "usAAPL.OQ")),
        (["特斯拉", "tsla"], MarketInstrument(namespace: .unitedStates, symbol: "TSLA", name: "特斯拉", eastmoneySecID: "105.TSLA", tencentCode: "usTSLA.OQ")),
        (["微软", "msft"], MarketInstrument(namespace: .unitedStates, symbol: "MSFT", name: "微软", eastmoneySecID: "105.MSFT", tencentCode: "usMSFT.OQ")),
        (["谷歌", "google", "googl"], MarketInstrument(namespace: .unitedStates, symbol: "GOOGL", name: "谷歌-A", eastmoneySecID: "105.GOOGL", tencentCode: "usGOOGL.OQ")),
        (["纳指etf", "纳斯达克", "qqq"], MarketInstrument(namespace: .unitedStates, symbol: "QQQ", name: "纳指100ETF", eastmoneySecID: "105.QQQ", tencentCode: "usQQQ.OQ")),
        (["标普500", "spy"], MarketInstrument(namespace: .unitedStates, symbol: "SPY", name: "标普500ETF", eastmoneySecID: "107.SPY", tencentCode: "usSPY.AM")),
    ]
    
    
    static func resolve(_ rawQuery: String) -> MarketInstrument? {
        let lower = rawQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !lower.isEmpty else { return nil }
        
        for entry in Self.catalog {
            if entry.aliases.contains(lower) {
                return entry.instrument
            }
        }
        for entry in Self.catalog {
            if entry.aliases.contains(where: { $0.count >= 2 && lower.contains($0) }) {
                return entry.instrument
            }
        }
        return nil
    }
}
