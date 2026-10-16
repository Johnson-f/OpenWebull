import Foundation

/// Price alerts that fire once when the last price crosses the requested level.
@MainActor
final class AlertStore {
    struct PriceAlert: Identifiable {
        let id = UUID()
        let symbol: String
        let price: Double
        let triggersAbove: Bool
        let createdAt: Date
        var triggeredAt: Date?
    }

    let changed = Signal<Void>()
    let triggered = Signal<PriceAlert>()

    private(set) var alerts: [PriceAlert] = []

    func add(symbol: String, price: Double, currentPrice: Double, now: Date = Date()) {
        alerts.insert(PriceAlert(symbol: symbol, price: price, triggersAbove: price >= currentPrice, createdAt: now), at: 0)
        changed.send()
    }

    func remove(_ id: UUID) {
        alerts.removeAll { $0.id == id }
        changed.send()
    }

    func evaluate(quotes: QuoteProviding, now: Date = Date()) {
        var fired: [PriceAlert] = []
        for index in alerts.indices where alerts[index].triggeredAt == nil {
            guard let last = quotes.quote(for: alerts[index].symbol)?.last else { continue }
            let alert = alerts[index]
            if alert.triggersAbove ? last >= alert.price : last <= alert.price {
                alerts[index].triggeredAt = now
                fired.append(alerts[index])
            }
        }
        guard !fired.isEmpty else { return }
        fired.forEach(triggered.send)
        changed.send()
    }
}
