import Foundation
import Testing
@testable import OpenWebull

@MainActor
struct MarketSimulatorTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func historyIsDeterministicPerSymbol() {
        let first = MarketSimulator(now: now)
        let second = MarketSimulator(now: now)
        #expect(first.candles(for: "AAPL", interval: .day) == second.candles(for: "AAPL", interval: .day))
        #expect(first.quote(for: "NVDA")?.last == second.quote(for: "NVDA")?.last)
    }

    @Test func candlesAreWellFormed() {
        let market = MarketSimulator(now: now)
        for interval in ChartInterval.allCases {
            let candles = market.candles(for: "MSFT", interval: interval)
            #expect(!candles.isEmpty, "no candles for \(interval)")
            for candle in candles {
                #expect(candle.high >= max(candle.open, candle.close))
                #expect(candle.low <= min(candle.open, candle.close))
            }
            #expect(zip(candles, candles.dropFirst()).allSatisfy { $0.time < $1.time }, "\(interval) not strictly increasing")
        }
    }

    @Test func quoteMatchesTodaysSession() throws {
        let market = MarketSimulator(now: now)
        let quote = try #require(market.quote(for: "AAPL"))
        let today = try #require(market.candles(for: "AAPL", interval: .day).last)
        #expect(today.close == quote.last)
        #expect(today.high == quote.high)
        #expect(quote.bid < quote.ask)
        #expect(market.candles(for: "AAPL", interval: .day).dropLast().last?.close == quote.previousClose)
    }

    @Test func tickUpdatesCurrentBarAndTape() throws {
        let market = MarketSimulator(now: now)
        for step in 1...40 {
            market.tick(at: now.addingTimeInterval(Double(step) * 0.5))
        }
        let quote = try #require(market.quote(for: "TSLA"))
        let bar = try #require(market.candles(for: "TSLA", interval: .oneMinute).last)
        #expect(bar.close == quote.last)
        #expect(quote.high >= quote.last && quote.low <= quote.last)
        #expect(!market.recentTape(for: "TSLA").isEmpty)
        #expect(market.recentTape(for: "SPX").isEmpty)
    }

    @Test func orderBookIsOrderedAroundTheQuote() throws {
        let market = MarketSimulator(now: now)
        let book = market.orderBook(for: "AMD")
        let quote = try #require(market.quote(for: "AMD"))
        #expect(book.bids.first?.price == quote.bid)
        #expect(book.asks.first?.price == quote.ask)
        #expect(zip(book.bids, book.bids.dropFirst()).allSatisfy { $0.price > $1.price })
        #expect(zip(book.asks, book.asks.dropFirst()).allSatisfy { $0.price < $1.price })
        #expect(market.orderBook(for: "AMD").totalBidSize == book.totalBidSize, "book should be stable within a tick")
    }
}

@MainActor
struct PricingTests {
    @Test func blackScholesSatisfiesPutCallParity() {
        let model = BlackScholes(spot: 100, strike: 105, years: 0.25, rate: 0.04, volatility: 0.3)
        let parity = model.callPrice - model.putPrice - (100 - 105 * exp(-0.04 * 0.25))
        #expect(abs(parity) < 1e-9)
        #expect(model.callDelta > 0 && model.callDelta < 1)
        #expect(abs(model.callDelta - model.putDelta - 1) < 1e-12)
    }

    @Test func movingAverageMatchesManualComputation() {
        let averages = CandleChartView.simpleMovingAverage([1, 2, 3, 4, 5], period: 3)
        #expect(averages[0] == nil && averages[1] == nil)
        #expect(averages[2] == 2)
        #expect(averages[4] == 4)
    }

    @Test func niceStepRoundsToReadableIncrements() {
        #expect(CandleChartView.niceStep(for: 0.37) == 0.5)
        #expect(CandleChartView.niceStep(for: 13) == 10)
        #expect(CandleChartView.niceStep(for: 2.2) == 2)
    }

    @Test func compactFormatting() {
        #expect(Format.compact(1_234_567) == "1.23M")
        #expect(Format.compact(2.5e12) == "2.50T")
        #expect(Format.percent(0.0123) == "+1.23%")
        #expect(Format.signedCurrency(-12.5) == "-$12.50")
    }
}
