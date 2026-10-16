import Foundation

/// Deterministic, clearly fictional research content for the stock detail tabs.
enum ResearchGenerator {
    struct CorporateAction {
        let date: Date
        let kind: String
        let detail: String
    }

    struct Holder {
        let name: String
        let shares: Double
        let percentOutstanding: Double
        let changeShares: Double
        let reportedAt: Date
    }

    struct Post {
        let author: String
        let time: Date
        let text: String
        let isBullish: Bool
        let likes: Int
    }

    struct QuarterFinancials {
        let period: String
        let revenue: Double
        let grossProfit: Double
        let operatingIncome: Double
        let netIncome: Double
        let eps: Double
    }

    struct EarningsRelease {
        let date: Date
        let period: String
        let epsEstimate: Double
        let epsActual: Double?
        let revenueEstimate: Double
        let revenueActual: Double?
    }

    private static let fundNames = [
        "Northbridge Capital", "Harborline Investors", "Granite Peak Advisors", "Silverleaf Asset Mgmt",
        "Bluewater Index Funds", "Meridian Pension Trust", "Oakhurst Partners", "Cobalt Street Capital",
        "Evergreen Retirement Fund", "Lanternfish Global", "Summit Ridge Holdings", "Tidewater Quant",
    ]

    private static let handles = [
        "paper_hands_pete", "thetagang_tina", "chartwatcher", "dividend_dan", "momentum_mia",
        "valuehunter", "scalper_sam", "longterm_lou", "gamma_gary", "swing_sara",
    ]

    private static let bullishPosts: [@Sendable (String) -> String] = [
        { "Holding \($0) through earnings, volume looks constructive." },
        { "\($0) reclaimed the 20 MA on the 5m — watching for continuation." },
        { "Added a starter position in \($0) on the pullback." },
        { "Higher lows all morning on \($0). Patience pays." },
    ]

    private static let bearishPosts: [@Sendable (String) -> String] = [
        { "\($0) rejected at the high of day again, taking profits." },
        { "Not loving the volume on this \($0) bounce." },
        { "Trimmed \($0) into strength, will re-enter lower." },
        { "\($0) looks extended here, waiting for a better entry." },
    ]

    static func corporateActions(for instrument: Instrument, now: Date) -> [CorporateAction] {
        var rng = SeededGenerator(string: instrument.symbol + "#actions")
        var actions: [CorporateAction] = []
        let calendar = Calendar.current
        let dividend = instrument.earningsPerShare > 1 ? (instrument.earningsPerShare * rng.double(in: 0.08...0.3) / 4) : 0
        for quarter in 0..<8 {
            let date = calendar.date(byAdding: .day, value: -quarter * 91 - rng.int(in: 0...20), to: now)!
            if dividend > 0 {
                actions.append(CorporateAction(date: date, kind: "Cash Dividend", detail: String(format: "$%.4f per share · Ex-date %@", dividend, Format.shortDate(date))))
            }
            actions.append(CorporateAction(date: calendar.date(byAdding: .day, value: -12, to: date)!, kind: "Earnings", detail: "Q\(4 - quarter % 4) results released after market close"))
        }
        if rng.unit() < 0.4 {
            actions.append(CorporateAction(date: calendar.date(byAdding: .year, value: -2, to: now)!, kind: "Stock Split", detail: "\(rng.int(in: 2...4))-for-1 forward split"))
        }
        actions.append(CorporateAction(date: calendar.date(byAdding: .day, value: rng.int(in: 10...60), to: now)!, kind: "Upcoming Earnings", detail: "Estimated date, before market open"))
        return actions.sorted { $0.date > $1.date }
    }

    static func institutions(for instrument: Instrument, now: Date) -> [Holder] {
        var rng = SeededGenerator(string: instrument.symbol + "#holders")
        var remaining = 0.65
        return fundNames.shuffled(using: &rng).prefix(10).map { name in
            let percent = remaining * rng.double(in: 0.08...0.22)
            remaining -= percent
            let shares = instrument.sharesOutstanding * percent
            return Holder(
                name: name, shares: shares, percentOutstanding: percent,
                changeShares: shares * rng.double(in: -0.08...0.1),
                reportedAt: Calendar.current.date(byAdding: .day, value: -rng.int(in: 20...110), to: now)!
            )
        }
        .sorted { $0.shares > $1.shares }
    }

    static func posts(for instrument: Instrument, now: Date) -> [Post] {
        var rng = SeededGenerator(string: instrument.symbol + "#posts")
        return (0..<30).map { index in
            let bullish = rng.unit() < 0.55
            let template = (bullish ? bullishPosts : bearishPosts).randomElement(using: &rng)!
            return Post(
                author: handles.randomElement(using: &rng)!,
                time: now.addingTimeInterval(-Double(index) * rng.double(in: 300...2_400)),
                text: template(instrument.symbol), isBullish: bullish, likes: rng.int(in: 0...240)
            )
        }
    }

    static func financials(for instrument: Instrument, now: Date) -> [QuarterFinancials] {
        var rng = SeededGenerator(string: instrument.symbol + "#financials")
        let annualNetIncome = instrument.earningsPerShare * instrument.sharesOutstanding
        let margin = rng.double(in: 0.08...0.32)
        let annualRevenue = abs(annualNetIncome) / margin
        let year = Calendar.current.component(.year, from: now)
        return (0..<8).map { offset in
            let growth = pow(1 - rng.double(in: 0.0...0.05), Double(offset))
            let revenue = annualRevenue / 4 * growth * rng.double(in: 0.94...1.06)
            let net = annualNetIncome / 4 * growth * rng.double(in: 0.85...1.15)
            return QuarterFinancials(
                period: "Q\(4 - offset % 4) \(year - 1 - offset / 4)",
                revenue: revenue, grossProfit: revenue * rng.double(in: 0.35...0.7),
                operatingIncome: net * rng.double(in: 1.1...1.35), netIncome: net,
                eps: instrument.sharesOutstanding > 0 ? net / instrument.sharesOutstanding : 0
            )
        }
    }

    static func releases(for instrument: Instrument, now: Date) -> [EarningsRelease] {
        let quarters = financials(for: instrument, now: now)
        var rng = SeededGenerator(string: instrument.symbol + "#releases")
        let calendar = Calendar.current
        var releases = quarters.enumerated().map { offset, quarter in
            EarningsRelease(
                date: calendar.date(byAdding: .day, value: -(offset + 1) * 91, to: now)!,
                period: quarter.period,
                epsEstimate: quarter.eps * rng.double(in: 0.9...1.08), epsActual: quarter.eps,
                revenueEstimate: quarter.revenue * rng.double(in: 0.95...1.04), revenueActual: quarter.revenue
            )
        }
        if let latest = quarters.first {
            releases.insert(EarningsRelease(
                date: calendar.date(byAdding: .day, value: rng.int(in: 10...60), to: now)!, period: "Next quarter",
                epsEstimate: latest.eps * 1.03, epsActual: nil, revenueEstimate: latest.revenue * 1.02, revenueActual: nil
            ), at: 0)
        }
        return releases
    }
}
