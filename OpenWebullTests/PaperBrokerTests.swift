import Foundation
import Testing
@testable import OpenWebull

@MainActor
private final class StubQuotes: QuoteProviding {
    var quotes: [String: Quote] = [:]

    func set(_ symbol: String, bid: Double, ask: Double, last: Double? = nil, previousClose: Double? = nil) {
        let price = last ?? (bid + ask) / 2
        quotes[symbol] = Quote(
            symbol: symbol, last: price, open: price, high: price, low: price,
            previousClose: previousClose ?? price, volume: 0,
            bid: bid, ask: ask, bidSize: 100, askSize: 100, updatedAt: Date()
        )
    }

    func quote(for symbol: String) -> Quote? {
        quotes[symbol]
    }
}

@MainActor
struct PaperBrokerTests {
    private let quotes = StubQuotes()
    private let broker: PaperBroker

    init() {
        broker = PaperBroker(quotes: quotes, instrumentLookup: { InstrumentCatalog.bySymbol[$0] }, startingCash: 10_000)
        quotes.set("AAPL", bid: 99.99, ask: 100.01)
    }

    private func ticket(_ side: OrderSide, _ quantity: Int, type: OrderType = .market, limit: Double? = nil, stop: Double? = nil, tif: TimeInForce = .day) -> OrderTicket {
        OrderTicket(symbol: "AAPL", side: side, type: type, quantity: quantity, limitPrice: limit, stopPrice: stop, timeInForce: tif)
    }

    @Test func marketBuyFillsAtAsk() throws {
        let order = try broker.place(ticket(.buy, 10)).get()
        #expect(order.status == .filled)
        #expect(order.averageFillPrice == 100.01)
        #expect(broker.position(for: "AAPL")?.quantity == 10)
        #expect(abs(broker.cash - (10_000 - 1_000.10)) < 1e-9)
    }

    @Test func limitBuyRestsUntilAskCrosses() throws {
        let order = try broker.place(ticket(.buy, 5, type: .limit, limit: 99.50)).get()
        #expect(order.status == .working)

        quotes.set("AAPL", bid: 99.40, ask: 99.45)
        broker.evaluateWorkingOrders()

        let filled = try #require(broker.orders.first { $0.id == order.id })
        #expect(filled.status == .filled)
        #expect(filled.averageFillPrice == 99.45)
    }

    @Test func sellStopTriggersOnLastAtOrBelowStop() throws {
        _ = try broker.place(ticket(.buy, 10)).get()
        let stop = try broker.place(ticket(.sell, 10, type: .stop, stop: 95)).get()
        #expect(stop.status == .working)

        quotes.set("AAPL", bid: 94.98, ask: 95.02, last: 95)
        broker.evaluateWorkingOrders()

        #expect(broker.orders.first { $0.id == stop.id }?.status == .filled)
        #expect(broker.position(for: "AAPL") == nil)
    }

    @Test func immediateOrCancelLimitThatCannotFillIsCancelled() throws {
        let order = try broker.place(ticket(.buy, 5, type: .limit, limit: 90, tif: .immediateOrCancel)).get()
        #expect(order.status == .cancelled)
    }

    @Test func closingAPositionRealizesProfit() throws {
        _ = try broker.place(ticket(.buy, 10)).get()
        quotes.set("AAPL", bid: 110, ask: 110.02)
        _ = try broker.place(ticket(.sell, 10)).get()

        #expect(broker.position(for: "AAPL") == nil)
        #expect(abs(broker.realizedPnL - (110 - 100.01) * 10) < 1e-9)
    }

    @Test func sellingMoreThanHeldFlipsToShortAtFillPrice() throws {
        _ = try broker.place(ticket(.buy, 10)).get()
        _ = try broker.place(ticket(.sell, 15)).get()

        let position = try #require(broker.position(for: "AAPL"))
        #expect(position.quantity == -5)
        #expect(position.averageCost == 99.99)
    }

    @Test func averagesCostWhenAddingToAPosition() throws {
        _ = try broker.place(ticket(.buy, 10)).get()
        quotes.set("AAPL", bid: 109.99, ask: 110.01)
        _ = try broker.place(ticket(.buy, 10)).get()

        let position = try #require(broker.position(for: "AAPL"))
        #expect(abs(position.averageCost - 105.01) < 1e-9)
    }

    @Test func rejectsOrdersBeyondBuyingPower() {
        let result = broker.place(ticket(.buy, 1_000))
        guard case let .failure(rejection) = result, case .insufficientBuyingPower = rejection else {
            Issue.record("Expected an insufficient buying power rejection, got \(result)")
            return
        }
    }

    @Test func rejectsInvalidTickets() {
        #expect(throws: OrderRejection.invalidQuantity) { try broker.place(ticket(.buy, 0)).get() }
        #expect(throws: OrderRejection.missingLimitPrice) { try broker.place(ticket(.buy, 1, type: .limit)).get() }
        let index = OrderTicket(symbol: "SPX", side: .buy, type: .market, quantity: 1, timeInForce: .day)
        quotes.set("SPX", bid: 6_000, ask: 6_000)
        #expect(throws: OrderRejection.notTradable) { try broker.place(index).get() }
    }

    @Test func cancelStopsAWorkingOrder() throws {
        let order = try broker.place(ticket(.buy, 5, type: .limit, limit: 90)).get()
        broker.cancel(order.id)
        quotes.set("AAPL", bid: 89, ask: 89.02)
        broker.evaluateWorkingOrders()
        #expect(broker.orders.first { $0.id == order.id }?.status == .cancelled)
        #expect(broker.position(for: "AAPL") == nil)
    }

    @Test func snapshotValuesLongAndShortPositions() throws {
        _ = try broker.place(ticket(.buy, 10)).get()
        quotes.set("AAPL", bid: 104.99, ask: 105.01, last: 105)
        let snapshot = broker.snapshot()
        #expect(abs(snapshot.longMarketValue - 1_050) < 1e-9)
        #expect(abs(snapshot.unrealizedPnL - (105 - 100.01) * 10) < 1e-9)
        #expect(abs(snapshot.netLiquidation - (snapshot.cash + 1_050)) < 1e-9)
    }
}
