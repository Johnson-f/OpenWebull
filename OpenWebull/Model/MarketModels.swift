import Foundation

struct Instrument: Hashable, Sendable {
    enum Kind: String, Sendable {
        case stock = "Stock"
        case etf = "ETF"
        case index = "Index"
    }

    let symbol: String
    let name: String
    let exchange: String
    let sector: String
    let kind: Kind
    let referencePrice: Double
    /// Annualised volatility used to drive the random walk.
    let volatility: Double
    let sharesOutstanding: Double
    let earningsPerShare: Double

    var isTradable: Bool { kind != .index }
}

struct Quote: Sendable {
    let symbol: String
    var last: Double
    var open: Double
    var high: Double
    var low: Double
    var previousClose: Double
    var volume: Double
    var bid: Double
    var ask: Double
    var bidSize: Int
    var askSize: Int
    var updatedAt: Date

    var change: Double { last - previousClose }
    var changePercent: Double { previousClose == 0 ? 0 : change / previousClose }
    var mid: Double { (bid + ask) / 2 }
    var spread: Double { ask - bid }
}

struct Candle: Sendable, Equatable {
    var time: Date
    var open: Double
    var high: Double
    var low: Double
    var close: Double
    var volume: Double

    mutating func absorb(_ other: Candle) {
        high = max(high, other.high)
        low = min(low, other.low)
        close = other.close
        volume += other.volume
    }
}

enum ChartInterval: String, CaseIterable, Sendable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case day = "D"
    case week = "W"
    case month = "M"

    var isIntraday: Bool {
        switch self {
        case .oneMinute, .fiveMinutes, .fifteenMinutes, .thirtyMinutes, .oneHour: true
        case .day, .week, .month: false
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .thirtyMinutes: 1800
        case .oneHour: 3600
        case .day: 86_400
        case .week: 604_800
        case .month: 2_592_000
        }
    }

    var title: String {
        switch self {
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .day: "Daily"
        case .week: "Weekly"
        case .month: "Monthly"
        }
    }
}

struct BookLevel: Sendable {
    let price: Double
    let size: Int
    let orderCount: Int
    let venue: String
}

struct OrderBook: Sendable {
    let symbol: String
    let bids: [BookLevel]
    let asks: [BookLevel]

    var totalBidSize: Int { bids.reduce(0) { $0 + $1.size } }
    var totalAskSize: Int { asks.reduce(0) { $0 + $1.size } }
}

struct TapePrint: Sendable {
    enum Aggressor: Sendable {
        case buyer, seller, neutral
    }

    let time: Date
    let price: Double
    let size: Int
    let aggressor: Aggressor
    let venue: String
}

struct NewsItem: Sendable {
    let time: Date
    let symbol: String
    let headline: String
    let source: String
}
