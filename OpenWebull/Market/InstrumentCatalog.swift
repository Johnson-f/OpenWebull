import Foundation

/// Fictional reference data. Prices, fundamentals and volatilities are invented for simulation.
enum InstrumentCatalog {
    static let indices: [Instrument] = [
        index("DJI", "Dow Jones Industrial Average", 44_120, 0.14),
        index("SPX", "S&P 500 Index", 6_215, 0.15),
        index("IXIC", "Nasdaq Composite", 20_480, 0.19),
        index("RUT", "Russell 2000", 2_265, 0.21),
        index("VIX", "CBOE Volatility Index", 16.4, 0.85),
    ]

    static let equities: [Instrument] = [
        stock("AAPL", "Apple Inc", "NASDAQ", "Technology", 228.40, 0.24, 15.1e9, 6.6),
        stock("MSFT", "Microsoft Corp", "NASDAQ", "Technology", 492.10, 0.22, 7.43e9, 12.4),
        stock("NVDA", "NVIDIA Corp", "NASDAQ", "Semiconductors", 171.25, 0.46, 24.4e9, 3.1),
        stock("AMZN", "Amazon.com Inc", "NASDAQ", "Consumer Cyclical", 219.80, 0.30, 10.6e9, 5.5),
        stock("GOOGL", "Alphabet Inc Class A", "NASDAQ", "Communication", 192.60, 0.27, 12.2e9, 8.9),
        stock("META", "Meta Platforms Inc", "NASDAQ", "Communication", 702.30, 0.33, 2.52e9, 25.6),
        stock("TSLA", "Tesla Inc", "NASDAQ", "Consumer Cyclical", 318.90, 0.58, 3.22e9, 1.8),
        stock("AMD", "Advanced Micro Devices", "NASDAQ", "Semiconductors", 158.70, 0.48, 1.62e9, 1.4),
        stock("AVGO", "Broadcom Inc", "NASDAQ", "Semiconductors", 285.10, 0.40, 4.7e9, 2.9),
        stock("INTC", "Intel Corp", "NASDAQ", "Semiconductors", 22.85, 0.42, 4.37e9, -4.4),
        stock("NFLX", "Netflix Inc", "NASDAQ", "Communication", 1_215.00, 0.36, 0.43e9, 22.0),
        stock("ORCL", "Oracle Corp", "NYSE", "Technology", 238.20, 0.34, 2.81e9, 4.3),
        stock("CRM", "Salesforce Inc", "NYSE", "Technology", 262.40, 0.31, 0.96e9, 6.4),
        stock("ADBE", "Adobe Inc", "NASDAQ", "Technology", 381.50, 0.30, 0.43e9, 15.9),
        stock("PLTR", "Palantir Technologies", "NASDAQ", "Technology", 152.30, 0.62, 2.36e9, 0.23),
        stock("SHOP", "Shopify Inc", "NASDAQ", "Technology", 118.60, 0.50, 1.30e9, 1.5),
        stock("UBER", "Uber Technologies", "NYSE", "Industrials", 92.40, 0.38, 2.09e9, 4.6),
        stock("COIN", "Coinbase Global", "NASDAQ", "Financials", 345.70, 0.72, 0.25e9, 9.8),
        stock("JPM", "JPMorgan Chase & Co", "NYSE", "Financials", 291.20, 0.20, 2.78e9, 19.8),
        stock("BAC", "Bank of America Corp", "NYSE", "Financials", 47.60, 0.24, 7.55e9, 3.2),
        stock("GS", "Goldman Sachs Group", "NYSE", "Financials", 712.80, 0.26, 0.31e9, 41.0),
        stock("V", "Visa Inc", "NYSE", "Financials", 351.90, 0.18, 1.95e9, 10.2),
        stock("XOM", "Exxon Mobil Corp", "NYSE", "Energy", 111.40, 0.22, 4.31e9, 7.6),
        stock("CVX", "Chevron Corp", "NYSE", "Energy", 152.10, 0.23, 1.75e9, 9.7),
        stock("JNJ", "Johnson & Johnson", "NYSE", "Healthcare", 156.80, 0.16, 2.41e9, 5.8),
        stock("LLY", "Eli Lilly and Co", "NYSE", "Healthcare", 781.30, 0.32, 0.90e9, 12.0),
        stock("PFE", "Pfizer Inc", "NYSE", "Healthcare", 24.90, 0.24, 5.67e9, 1.4),
        stock("UNH", "UnitedHealth Group", "NYSE", "Healthcare", 312.40, 0.35, 0.91e9, 24.0),
        stock("WMT", "Walmart Inc", "NYSE", "Consumer Defensive", 97.80, 0.18, 8.0e9, 2.5),
        stock("COST", "Costco Wholesale", "NASDAQ", "Consumer Defensive", 986.20, 0.19, 0.44e9, 17.0),
        stock("KO", "Coca-Cola Co", "NYSE", "Consumer Defensive", 70.10, 0.14, 4.31e9, 2.5),
        stock("DIS", "Walt Disney Co", "NYSE", "Communication", 121.30, 0.27, 1.81e9, 3.0),
        stock("BA", "Boeing Co", "NYSE", "Industrials", 218.60, 0.36, 0.75e9, -14.0),
        stock("CAT", "Caterpillar Inc", "NYSE", "Industrials", 386.70, 0.27, 0.47e9, 21.0),
        stock("F", "Ford Motor Co", "NYSE", "Consumer Cyclical", 11.35, 0.33, 3.98e9, 1.2),
        stock("SOFI", "SoFi Technologies", "NASDAQ", "Financials", 18.40, 0.60, 1.10e9, 0.39),
        stock("RIVN", "Rivian Automotive", "NASDAQ", "Consumer Cyclical", 13.20, 0.66, 1.13e9, -4.1),
        stock("GME", "GameStop Corp", "NYSE", "Consumer Cyclical", 23.60, 0.80, 0.45e9, 0.3),
        etf("SPY", "SPDR S&P 500 ETF Trust", 619.40, 0.15),
        etf("QQQ", "Invesco QQQ Trust", 551.20, 0.19),
        etf("IWM", "iShares Russell 2000 ETF", 223.70, 0.21),
        etf("TLT", "iShares 20+ Year Treasury Bond ETF", 86.90, 0.16),
    ]

    static let all: [Instrument] = indices + equities

    static let bySymbol: [String: Instrument] = Dictionary(uniqueKeysWithValues: all.map { ($0.symbol, $0) })

    static var sectors: [String] {
        Array(Set(equities.filter { $0.kind == .stock }.map(\.sector))).sorted()
    }

    private static func stock(
        _ symbol: String, _ name: String, _ exchange: String, _ sector: String,
        _ price: Double, _ volatility: Double, _ shares: Double, _ eps: Double
    ) -> Instrument {
        Instrument(
            symbol: symbol, name: name, exchange: exchange, sector: sector, kind: .stock,
            referencePrice: price, volatility: volatility, sharesOutstanding: shares, earningsPerShare: eps
        )
    }

    private static func etf(_ symbol: String, _ name: String, _ price: Double, _ volatility: Double) -> Instrument {
        Instrument(
            symbol: symbol, name: name, exchange: "NYSE ARCA", sector: "ETF", kind: .etf,
            referencePrice: price, volatility: volatility, sharesOutstanding: 0.9e9, earningsPerShare: 0
        )
    }

    private static func index(_ symbol: String, _ name: String, _ level: Double, _ volatility: Double) -> Instrument {
        Instrument(
            symbol: symbol, name: name, exchange: "INDEX", sector: "Index", kind: .index,
            referencePrice: level, volatility: volatility, sharesOutstanding: 0, earningsPerShare: 0
        )
    }
}
