import Foundation

/// Produces obviously synthetic headlines so the news panels have plausible-looking content.
enum NewsGenerator {
    private static let sources = ["Simulated Wire", "Demo Markets Desk", "Sample Newswire", "Paper Street Journal"]

    private static let templates: [@Sendable (String) -> String] = [
        { "\($0) shares move as traders weigh sector rotation" },
        { "Analysts revisit price targets on \($0) ahead of earnings" },
        { "\($0) announces expanded share repurchase program" },
        { "Options activity in \($0) picks up into the afternoon" },
        { "\($0) to present at upcoming industry conference" },
        { "Institutional filings show shifting positions in \($0)" },
        { "\($0) unveils new product roadmap at investor event" },
        { "Unusual volume spotted in \($0) during morning session" },
        { "\($0) declares quarterly dividend" },
        { "Short interest in \($0) edges lower, data shows" },
        { "\($0) leadership comments on demand outlook" },
        { "Supply-chain update lifts sentiment around \($0)" },
    ]

    static func initialFeed(for instruments: [Instrument], now: Date, rng: inout SeededGenerator) -> [NewsItem] {
        (0..<160).map { _ in
            let instrument = instruments.randomElement(using: &rng)!
            let age = rng.double(in: 60...(3 * 86_400))
            return headline(for: instrument, at: now.addingTimeInterval(-age), rng: &rng)
        }
        .sorted { $0.time > $1.time }
    }

    static func headline(for instrument: Instrument, at time: Date, rng: inout SeededGenerator) -> NewsItem {
        let template = templates.randomElement(using: &rng)!
        return NewsItem(
            time: time,
            symbol: instrument.symbol,
            headline: template(instrument.name),
            source: sources.randomElement(using: &rng)!
        )
    }
}
