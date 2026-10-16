import Foundation

/// A margin paper-trading account that fills orders against the simulated quotes.
@MainActor
final class PaperBroker {
    static let marginMultiplier = 2.0

    let changed = Signal<Void>()
    let orderFilled = Signal<Order>()

    private(set) var orders: [Order] = []
    private(set) var positions: [String: Position] = [:]
    private(set) var cash: Double
    private(set) var realizedPnL = 0.0
    private var startOfDayEquity: Double

    private let quotes: QuoteProviding
    private let instrumentLookup: (String) -> Instrument?

    init(quotes: QuoteProviding, instrumentLookup: @escaping (String) -> Instrument?, startingCash: Double = 100_000) {
        self.quotes = quotes
        self.instrumentLookup = instrumentLookup
        cash = startingCash
        startOfDayEquity = startingCash
    }

    var sortedPositions: [Position] {
        positions.values.sorted { abs(marketValue($0)) > abs(marketValue($1)) }
    }

    var workingOrders: [Order] {
        orders.filter { $0.status.isOpen }
    }

    func position(for symbol: String) -> Position? {
        positions[symbol]
    }

    // MARK: Order entry

    @discardableResult
    func place(_ ticket: OrderTicket, now: Date = Date()) -> Result<Order, OrderRejection> {
        if let rejection = validate(ticket) {
            return .failure(rejection)
        }
        var order = Order(id: UUID(), ticket: ticket, createdAt: now, status: .working, updatedAt: now)
        attemptFill(&order, now: now)
        if order.status == .working, ticket.timeInForce == .immediateOrCancel {
            order.status = .cancelled
            order.note = "IOC: no immediate fill"
        }
        orders.insert(order, at: 0)
        changed.send()
        return .success(order)
    }

    func cancel(_ id: UUID, now: Date = Date()) {
        guard let index = orders.firstIndex(where: { $0.id == id }), orders[index].status.isOpen else { return }
        orders[index].status = .cancelled
        orders[index].updatedAt = now
        changed.send()
    }

    func cancelAllWorkingOrders(now: Date = Date()) {
        for index in orders.indices where orders[index].status.isOpen {
            orders[index].status = .cancelled
            orders[index].updatedAt = now
        }
        changed.send()
    }

    @discardableResult
    func closePosition(_ symbol: String) -> Result<Order, OrderRejection>? {
        guard let position = positions[symbol], position.quantity != 0 else { return nil }
        return place(OrderTicket(
            symbol: symbol, side: position.isShort ? .buy : .sell, type: .market,
            quantity: abs(position.quantity), timeInForce: .day
        ))
    }

    /// Called on every market tick to trigger stops and fill resting limit orders.
    func evaluateWorkingOrders(now: Date = Date()) {
        var didChange = false
        for index in orders.indices where orders[index].status.isOpen {
            let before = orders[index].status
            let wasTriggered = orders[index].stopTriggered
            attemptFill(&orders[index], now: now)
            didChange = didChange || before != orders[index].status || wasTriggered != orders[index].stopTriggered
        }
        if didChange || !positions.isEmpty {
            changed.send()
        }
    }

    // MARK: Account

    func snapshot() -> AccountSnapshot {
        var longValue = 0.0
        var shortValue = 0.0
        var unrealized = 0.0
        for position in positions.values {
            let price = lastPrice(position.symbol) ?? position.averageCost
            let value = position.marketValue(at: price)
            if value >= 0 { longValue += value } else { shortValue += value }
            unrealized += position.unrealizedPnL(at: price)
        }
        let netLiquidation = cash + longValue + shortValue
        let buyingPower = max(0, netLiquidation * Self.marginMultiplier - (longValue - shortValue))
        return AccountSnapshot(
            cash: cash, longMarketValue: longValue, shortMarketValue: shortValue,
            unrealizedPnL: unrealized, realizedPnL: realizedPnL,
            dayPnL: netLiquidation - startOfDayEquity, buyingPower: buyingPower
        )
    }

    func reset(startingCash: Double = 100_000) {
        orders = []
        positions = [:]
        cash = startingCash
        realizedPnL = 0
        startOfDayEquity = startingCash
        changed.send()
    }

    /// Builds a believable starting portfolio with cost bases away from today's prices.
    func seedDemoPortfolio(now: Date = Date()) {
        let holdings: [(String, Int, Double)] = [
            ("AAPL", 60, -0.12), ("NVDA", 120, -0.31), ("MSFT", 25, -0.06),
            ("TSLA", -15, 0.04), ("SPY", 30, -0.08), ("AMD", 50, 0.09), ("SOFI", 400, -0.22),
        ]
        for (symbol, quantity, costOffset) in holdings {
            guard let quote = quotes.quote(for: symbol) else { continue }
            let cost = ((quote.previousClose * (1 + costOffset)) * 100).rounded() / 100
            applyFill(symbol: symbol, side: quantity > 0 ? .buy : .sell, quantity: abs(quantity), price: cost)
            var order = Order(
                id: UUID(),
                ticket: OrderTicket(symbol: symbol, side: quantity > 0 ? .buy : .sell, type: .limit, quantity: abs(quantity), limitPrice: cost, timeInForce: .goodTillCancelled),
                createdAt: now.addingTimeInterval(-Double.random(in: 86_400...(40 * 86_400))),
                status: .filled, updatedAt: now
            )
            order.filledQuantity = abs(quantity)
            order.averageFillPrice = cost
            orders.append(order)
        }
        orders.sort { $0.createdAt > $1.createdAt }
        realizedPnL = 0
        startOfDayEquity = cash + positions.values.reduce(0) { total, position in
            total + position.marketValue(at: quotes.quote(for: position.symbol)?.previousClose ?? position.averageCost)
        }
        if let quote = quotes.quote(for: "META") {
            place(OrderTicket(symbol: "META", side: .buy, type: .limit, quantity: 10, limitPrice: ((quote.bid * 0.97) * 100).rounded() / 100, timeInForce: .goodTillCancelled), now: now)
        }
        changed.send()
    }

    // MARK: Internals

    private func validate(_ ticket: OrderTicket) -> OrderRejection? {
        guard ticket.quantity > 0 else { return .invalidQuantity }
        guard let instrument = instrumentLookup(ticket.symbol), let quote = quotes.quote(for: ticket.symbol) else { return .unknownSymbol }
        guard instrument.isTradable else { return .notTradable }
        if ticket.type.needsLimitPrice, (ticket.limitPrice ?? 0) <= 0 { return .missingLimitPrice }
        if ticket.type.needsStopPrice, (ticket.stopPrice ?? 0) <= 0 { return .missingStopPrice }

        let current = positions[ticket.symbol]?.quantity ?? 0
        let resulting = current + Int(ticket.side.sign) * ticket.quantity
        let addedShares = max(0, abs(resulting) - abs(current))
        let referencePrice = ticket.limitPrice ?? ticket.stopPrice ?? (ticket.side == .buy ? quote.ask : quote.bid)
        let required = Double(addedShares) * referencePrice
        let available = snapshot().buyingPower - reservedBuyingPower()
        if required > available {
            return .insufficientBuyingPower(required: required, available: max(0, available))
        }
        return nil
    }

    private func reservedBuyingPower() -> Double {
        workingOrders.reduce(0) { total, order in
            total + Double(order.remainingQuantity) * (order.ticket.limitPrice ?? order.ticket.stopPrice ?? 0)
        }
    }

    private func attemptFill(_ order: inout Order, now: Date) {
        guard let quote = quotes.quote(for: order.symbol) else { return }
        let ticket = order.ticket
        let isBuy = ticket.side == .buy

        if ticket.type.needsStopPrice, !order.stopTriggered, let stop = ticket.stopPrice {
            let triggered = isBuy ? quote.last >= stop : quote.last <= stop
            guard triggered else { return }
            order.stopTriggered = true
            order.updatedAt = now
        }

        let marketPrice = isBuy ? quote.ask : quote.bid
        let fillPrice: Double?
        switch ticket.type {
        case .market, .stop:
            fillPrice = marketPrice
        case .limit, .stopLimit:
            guard let limit = ticket.limitPrice else { return }
            fillPrice = (isBuy ? marketPrice <= limit : marketPrice >= limit) ? marketPrice : nil
        }
        guard let price = fillPrice else { return }

        applyFill(symbol: ticket.symbol, side: ticket.side, quantity: order.remainingQuantity, price: price)
        order.averageFillPrice = price
        order.filledQuantity = ticket.quantity
        order.status = .filled
        order.updatedAt = now
        orderFilled.send(order)
    }

    private func applyFill(symbol: String, side: OrderSide, quantity: Int, price: Double) {
        let signedQuantity = Int(side.sign) * quantity
        cash -= Double(signedQuantity) * price

        var position = positions[symbol] ?? Position(symbol: symbol, quantity: 0, averageCost: 0)
        let isIncreasing = position.quantity == 0 || (position.quantity > 0) == (signedQuantity > 0)
        if isIncreasing {
            let totalShares = abs(position.quantity) + quantity
            position.averageCost = (Double(abs(position.quantity)) * position.averageCost + Double(quantity) * price) / Double(totalShares)
            position.quantity += signedQuantity
        } else {
            let closing = min(abs(position.quantity), quantity)
            let direction: Double = position.quantity > 0 ? 1 : -1
            realizedPnL += Double(closing) * (price - position.averageCost) * direction
            position.quantity += signedQuantity
            if quantity > closing {
                position.averageCost = price
            }
        }
        positions[symbol] = position.quantity == 0 ? nil : position
    }

    private func lastPrice(_ symbol: String) -> Double? {
        quotes.quote(for: symbol)?.last
    }

    private func marketValue(_ position: Position) -> Double {
        position.marketValue(at: lastPrice(position.symbol) ?? position.averageCost)
    }
}
