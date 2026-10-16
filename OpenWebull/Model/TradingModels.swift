import Foundation

enum OrderSide: String, CaseIterable, Sendable {
    case buy = "Buy"
    case sell = "Sell"

    var sign: Double { self == .buy ? 1 : -1 }
}

enum OrderType: String, CaseIterable, Sendable {
    case market = "Market"
    case limit = "Limit"
    case stop = "Stop"
    case stopLimit = "Stop Limit"

    var needsLimitPrice: Bool { self == .limit || self == .stopLimit }
    var needsStopPrice: Bool { self == .stop || self == .stopLimit }
}

enum TimeInForce: String, CaseIterable, Sendable {
    case day = "Day"
    case goodTillCancelled = "GTC"
    case immediateOrCancel = "IOC"
}

enum OrderStatus: String, Sendable {
    case working = "Working"
    case filled = "Filled"
    case cancelled = "Cancelled"
    case rejected = "Rejected"

    var isOpen: Bool { self == .working }
}

struct OrderTicket: Sendable {
    var symbol: String
    var side: OrderSide
    var type: OrderType
    var quantity: Int
    var limitPrice: Double?
    var stopPrice: Double?
    var timeInForce: TimeInForce
}

struct Order: Identifiable, Sendable {
    let id: UUID
    let ticket: OrderTicket
    let createdAt: Date
    var status: OrderStatus
    var filledQuantity: Int = 0
    var averageFillPrice: Double?
    var updatedAt: Date
    var stopTriggered = false
    var note: String?

    var symbol: String { ticket.symbol }
    var remainingQuantity: Int { ticket.quantity - filledQuantity }
}

struct Position: Sendable {
    let symbol: String
    /// Signed: negative quantities are short positions.
    var quantity: Int
    var averageCost: Double

    var isShort: Bool { quantity < 0 }

    func marketValue(at price: Double) -> Double {
        Double(quantity) * price
    }

    func unrealizedPnL(at price: Double) -> Double {
        Double(quantity) * (price - averageCost)
    }

    func unrealizedPnLPercent(at price: Double) -> Double {
        averageCost == 0 ? 0 : (price - averageCost) / averageCost * (isShort ? -1 : 1)
    }
}

struct AccountSnapshot: Sendable {
    let cash: Double
    let longMarketValue: Double
    let shortMarketValue: Double
    let unrealizedPnL: Double
    let realizedPnL: Double
    let dayPnL: Double
    let buyingPower: Double

    var netLiquidation: Double { cash + longMarketValue + shortMarketValue }
}

enum OrderRejection: Error, Equatable, Sendable {
    case invalidQuantity
    case missingLimitPrice
    case missingStopPrice
    case unknownSymbol
    case notTradable
    case insufficientBuyingPower(required: Double, available: Double)

    var message: String {
        switch self {
        case .invalidQuantity: "Quantity must be greater than zero."
        case .missingLimitPrice: "Enter a limit price."
        case .missingStopPrice: "Enter a stop price."
        case .unknownSymbol: "Unknown symbol."
        case .notTradable: "Indices can't be traded directly."
        case let .insufficientBuyingPower(required, available):
            "Insufficient buying power: needs \(Format.currency(required)), available \(Format.currency(available))."
        }
    }
}
