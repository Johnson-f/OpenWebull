import Foundation

/// The shared services every workspace and panel is built from.
@MainActor
final class AppEnvironment {
    let market: MarketSimulator
    let broker: PaperBroker
    let link: SymbolLink
    let watchlists: WatchlistStore
    let alerts = AlertStore()
    /// Clicking a price in a depth ladder or quote pre-fills the order ticket.
    let orderTicketPrice = Signal<Double>()

    init(market: MarketSimulator = MarketSimulator()) {
        self.market = market
        broker = PaperBroker(quotes: market, instrumentLookup: { [unowned market] in market.instrument($0) })
        link = SymbolLink(symbol: "AAPL")
        watchlists = WatchlistStore()

        broker.seedDemoPortfolio()
        market.ticked.observe(broker) { [unowned broker, unowned alerts, unowned market] in
            broker.evaluateWorkingOrders()
            alerts.evaluate(quotes: market)
        }
        link.changed.observe(watchlists) { [unowned watchlists] symbol in
            watchlists.recordRecentlyViewed(symbol)
        }
    }
}

/// The symbol every linked panel follows: picking a row in a watchlist retargets the chart,
/// level 2, time & sales and the order ticket together.
@MainActor
final class SymbolLink {
    let changed = Signal<String>()

    private(set) var symbol: String

    init(symbol: String) {
        self.symbol = symbol
    }

    func select(_ newSymbol: String) {
        guard newSymbol != symbol else { return }
        symbol = newSymbol
        changed.send(newSymbol)
    }
}

@MainActor
final class WatchlistStore {
    struct Watchlist: Codable, Equatable {
        var name: String
        var symbols: [String]
    }

    static let recentlyViewedName = "Recently Viewed"
    private static let defaultsKey = "watchlists.v1"
    private static let recentLimit = 30

    let changed = Signal<Void>()

    private(set) var lists: [Watchlist]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([Watchlist].self, from: data), !saved.isEmpty {
            lists = saved
        } else {
            lists = Self.defaultLists
        }
    }

    var names: [String] { lists.map(\.name) }

    func symbols(in name: String) -> [String] {
        lists.first { $0.name == name }?.symbols ?? []
    }

    func add(_ symbol: String, to name: String) {
        guard let index = lists.firstIndex(where: { $0.name == name }), !lists[index].symbols.contains(symbol) else { return }
        lists[index].symbols.append(symbol)
        persist()
    }

    func remove(_ symbol: String, from name: String) {
        guard let index = lists.firstIndex(where: { $0.name == name }) else { return }
        lists[index].symbols.removeAll { $0 == symbol }
        persist()
    }

    func recordRecentlyViewed(_ symbol: String) {
        guard let index = lists.firstIndex(where: { $0.name == Self.recentlyViewedName }) else { return }
        var symbols = lists[index].symbols.filter { $0 != symbol }
        symbols.insert(symbol, at: 0)
        lists[index].symbols = Array(symbols.prefix(Self.recentLimit))
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(lists) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
        changed.send()
    }

    private static let defaultLists = [
        Watchlist(name: "My Watchlist", symbols: ["AAPL", "NVDA", "MSFT", "TSLA", "AMZN", "META", "GOOGL", "AMD", "PLTR", "SPY", "QQQ"]),
        Watchlist(name: "Financials", symbols: ["JPM", "BAC", "GS", "V", "COIN", "SOFI"]),
        Watchlist(name: "Dividend", symbols: ["KO", "JNJ", "XOM", "CVX", "WMT", "PFE"]),
        Watchlist(name: recentlyViewedName, symbols: ["AAPL", "PLTR", "SOFI", "SPY", "QQQ", "TSLA", "NVDA"]),
    ]
}
