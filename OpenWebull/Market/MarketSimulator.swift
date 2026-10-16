import Foundation

@MainActor
protocol QuoteProviding: AnyObject {
    func quote(for symbol: String) -> Quote?
}

/// Generates a coherent, fake market: deterministic per-symbol history plus a live random walk
/// that drives quotes, the current bar, the order book and time & sales.
@MainActor
final class MarketSimulator: QuoteProviding {
    nonisolated static let sessionMinutes = 390
    static let elapsedSessionMinutes = 240
    static let priorIntradaySessions = 4
    static let dailyHistoryLength = 520
    static let tapeCapacity = 400
    static let tickInterval: Duration = .milliseconds(500)
    private static let ticksPerMinute = 120.0
    /// Makes intraday movement visible at a half-second cadence without being frantic.
    private static let liveVolatilityBoost = 3.0
    private static let venues = ["NSDQ", "ARCA", "EDGX", "BATS", "NYSE", "IEX", "MEMX", "DARK"]

    let instruments: [Instrument]
    let ticked = Signal<Void>()
    var speed = 1.0

    private(set) var quotes: [String: Quote] = [:]
    private(set) var tickCount: UInt64 = 0
    private(set) var news: [NewsItem] = []
    private var dailyHistory: [String: [Candle]] = [:]
    private var intradayBars: [String: [Candle]] = [:]
    private var tape: [String: [TapePrint]] = [:]
    private var sessionOpens: [String: Date] = [:]
    private var rng: SeededGenerator
    private var loop: Task<Void, Never>?
    private let instrumentsBySymbol: [String: Instrument]

    init(instruments: [Instrument] = InstrumentCatalog.all, now: Date = Date(), seed: UInt64 = 7) {
        self.instruments = instruments
        instrumentsBySymbol = Dictionary(uniqueKeysWithValues: instruments.map { ($0.symbol, $0) })
        rng = SeededGenerator(seed: seed)
        for instrument in instruments {
            seedHistory(for: instrument, now: now)
        }
        news = NewsGenerator.initialFeed(for: instruments.filter(\.isTradable), now: now, rng: &rng)
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                self?.tick()
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func instrument(_ symbol: String) -> Instrument? {
        instrumentsBySymbol[symbol]
    }

    func quote(for symbol: String) -> Quote? {
        quotes[symbol]
    }

    func sessionOpen(for symbol: String) -> Date? {
        sessionOpens[symbol]
    }

    // MARK: Live simulation

    func tick(at now: Date = Date()) {
        tickCount &+= 1
        for instrument in instruments {
            advance(instrument, now: now)
        }
        if rng.unit() < 0.04, let instrument = instruments.filter(\.isTradable).randomElement(using: &rng) {
            news.insert(NewsGenerator.headline(for: instrument, at: now, rng: &rng), at: 0)
            news = Array(news.prefix(300))
        }
        ticked.send()
    }

    private func advance(_ instrument: Instrument, now: Date) {
        guard var quote = quotes[instrument.symbol] else { return }
        let sigma = instrument.volatility / sqrt(252 * Double(Self.sessionMinutes) * Self.ticksPerMinute)
        let move = sigma * Self.liveVolatilityBoost * speed * rng.gaussian()
        let last = roundToTick(quote.last * exp(move))

        let printCount = instrument.isTradable ? rng.int(in: 0...3) : 0
        var prints: [TapePrint] = []
        var tickVolume = 0.0
        for _ in 0..<printCount {
            let size = lotSize(for: instrument)
            let aggressor: TapePrint.Aggressor = move > 0 ? .buyer : move < 0 ? .seller : .neutral
            let price = aggressor == .buyer ? quote.ask : aggressor == .seller ? quote.bid : last
            prints.append(TapePrint(time: now, price: price, size: size, aggressor: aggressor, venue: Self.venues.randomElement(using: &rng)!))
            tickVolume += Double(size)
        }
        if !instrument.isTradable {
            tickVolume = 0
        }

        quote.last = last
        quote.high = max(quote.high, last)
        quote.low = min(quote.low, last)
        quote.volume += tickVolume
        quote.updatedAt = now
        applySpread(to: &quote, instrument: instrument)
        quotes[instrument.symbol] = quote

        if !prints.isEmpty {
            var symbolTape = tape[instrument.symbol, default: []]
            symbolTape.append(contentsOf: prints)
            if symbolTape.count > Self.tapeCapacity {
                symbolTape.removeFirst(symbolTape.count - Self.tapeCapacity)
            }
            tape[instrument.symbol] = symbolTape
        }
        updateCurrentBar(symbol: instrument.symbol, price: last, volume: tickVolume, now: now)
    }

    private func updateCurrentBar(symbol: String, price: Double, volume: Double, now: Date) {
        let minute = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 60) * 60)
        var bars = intradayBars[symbol, default: []]
        if var current = bars.last, current.time == minute {
            current.absorb(Candle(time: minute, open: price, high: price, low: price, close: price, volume: volume))
            bars[bars.count - 1] = current
        } else {
            let open = bars.last?.close ?? price
            bars.append(Candle(time: minute, open: open, high: max(open, price), low: min(open, price), close: price, volume: volume))
        }
        intradayBars[symbol] = bars
    }

    // MARK: Queries

    func candles(for symbol: String, interval: ChartInterval) -> [Candle] {
        if interval.isIntraday {
            return aggregate(intradayBars[symbol] ?? []) { time in
                Date(timeIntervalSince1970: floor(time.timeIntervalSince1970 / interval.seconds) * interval.seconds)
            }
        }
        var days = dailyHistory[symbol] ?? []
        if let today = todayBar(for: symbol) {
            days.append(today)
        }
        let calendar = Calendar.current
        switch interval {
        case .week:
            return aggregate(days) { calendar.dateInterval(of: .weekOfYear, for: $0)?.start ?? $0 }
        case .month:
            return aggregate(days) { calendar.dateInterval(of: .month, for: $0)?.start ?? $0 }
        default:
            return days
        }
    }

    /// Today's 1-minute closes, used for sparklines.
    func sessionCloses(for symbol: String) -> [Double] {
        guard let open = sessionOpens[symbol] else { return [] }
        return (intradayBars[symbol] ?? []).filter { $0.time >= open }.map(\.close)
    }

    func recentTape(for symbol: String, limit: Int = 200) -> [TapePrint] {
        Array((tape[symbol] ?? []).suffix(limit).reversed())
    }

    func news(for symbol: String?) -> [NewsItem] {
        guard let symbol else { return news }
        return news.filter { $0.symbol == symbol }
    }

    /// The book is regenerated each tick but stays stable between ticks so repeated reads agree.
    func orderBook(for symbol: String, depth: Int = 12) -> OrderBook {
        guard let quote = quotes[symbol], let instrument = instrumentsBySymbol[symbol], instrument.isTradable else {
            return OrderBook(symbol: symbol, bids: [], asks: [])
        }
        var bookRNG = SeededGenerator(string: "\(symbol)#\(tickCount)")
        let step = priceIncrement(for: quote.last)
        func levels(from start: Double, direction: Double) -> [BookLevel] {
            (0..<depth).map { index in
                let price = roundToTick(start + direction * Double(index) * step)
                let roundNumberBoost = abs(price.truncatingRemainder(dividingBy: 1)) < 0.001 ? 3 : 1
                let size = (index == 0 ? (direction < 0 ? quote.bidSize : quote.askSize) : bookRNG.int(in: 1...40) * 100) * roundNumberBoost
                return BookLevel(price: price, size: size, orderCount: bookRNG.int(in: 1...18), venue: Self.venues[bookRNG.int(in: 0...(Self.venues.count - 2))])
            }
        }
        return OrderBook(symbol: symbol, bids: levels(from: quote.bid, direction: -1), asks: levels(from: quote.ask, direction: 1))
    }

    // MARK: History generation

    private func seedHistory(for instrument: Instrument, now: Date) {
        var generator = SeededGenerator(string: instrument.symbol)
        let minuteSigma = instrument.volatility / sqrt(252 * Double(Self.sessionMinutes))
        let daySigma = instrument.volatility / sqrt(252)
        let averageMinuteVolume = instrument.sharesOutstanding * 0.006 / Double(Self.sessionMinutes)

        let todayOpenTime = Date(timeIntervalSince1970: (floor(now.timeIntervalSince1970 / 60) - Double(Self.elapsedSessionMinutes - 1)) * 60)
        let previousClose = roundToTick(instrument.referencePrice * exp(0.02 * generator.gaussian()))

        let priorSessions = (1...Self.priorIntradaySessions).map { tradingDay(before: todayOpenTime, sessions: $0) }
        var cursor = previousClose
        var priorBars: [Candle] = []
        for sessionStart in priorSessions {
            var sessionBars: [Candle] = []
            for minute in stride(from: Self.sessionMinutes - 1, through: 0, by: -1) {
                let close = cursor
                let open = roundToTick(close / exp(minuteSigma * generator.gaussian()))
                let time = sessionStart.addingTimeInterval(Double(minute) * 60)
                sessionBars.append(makeBar(time: time, open: open, close: close, sigma: minuteSigma, volume: averageMinuteVolume, rng: &generator))
                cursor = open
            }
            priorBars.insert(contentsOf: sessionBars.reversed(), at: 0)
            cursor = roundToTick(cursor / exp(daySigma * 0.3 * generator.gaussian()))
        }

        var daily: [Candle] = []
        var dayCursor = cursor
        var dayTime = tradingDay(before: priorSessions.last!, sessions: 1)
        for _ in 0..<(Self.dailyHistoryLength - Self.priorIntradaySessions) {
            let close = dayCursor
            let open = roundToTick(close / exp(daySigma * generator.gaussian()))
            daily.append(makeBar(time: Calendar.current.startOfDay(for: dayTime), open: open, close: close, sigma: daySigma, volume: averageMinuteVolume * Double(Self.sessionMinutes), rng: &generator))
            dayCursor = open
            dayTime = tradingDay(before: dayTime, sessions: 1)
        }
        daily.reverse()
        for sessionStart in priorSessions.reversed() {
            let bars = priorBars.filter { Calendar.current.isDate($0.time, inSameDayAs: sessionStart) }
            if var day = bars.first {
                bars.dropFirst().forEach { day.absorb($0) }
                day.time = Calendar.current.startOfDay(for: sessionStart)
                daily.append(day)
            }
        }

        var todayBars: [Candle] = []
        var price = roundToTick(previousClose * exp(daySigma * 0.25 * generator.gaussian()))
        for minute in 0..<Self.elapsedSessionMinutes {
            let open = price
            let close = roundToTick(open * exp(minuteSigma * generator.gaussian()))
            todayBars.append(makeBar(time: todayOpenTime.addingTimeInterval(Double(minute) * 60), open: open, close: close, sigma: minuteSigma, volume: averageMinuteVolume, rng: &generator))
            price = close
        }

        intradayBars[instrument.symbol] = priorBars + todayBars
        dailyHistory[instrument.symbol] = daily
        sessionOpens[instrument.symbol] = todayOpenTime

        var session = todayBars[0]
        todayBars.dropFirst().forEach { session.absorb($0) }
        var quote = Quote(
            symbol: instrument.symbol, last: session.close, open: session.open, high: session.high, low: session.low,
            previousClose: previousClose, volume: instrument.isTradable ? session.volume : 0,
            bid: 0, ask: 0, bidSize: 0, askSize: 0, updatedAt: now
        )
        applySpread(to: &quote, instrument: instrument)
        quotes[instrument.symbol] = quote
    }

    private func makeBar(time: Date, open: Double, close: Double, sigma: Double, volume: Double, rng: inout SeededGenerator) -> Candle {
        let high = roundToTick(max(open, close) * (1 + abs(rng.gaussian()) * sigma * 0.6))
        let low = roundToTick(min(open, close) * (1 - abs(rng.gaussian()) * sigma * 0.6))
        return Candle(time: time, open: open, high: high, low: low, close: close, volume: (volume * rng.double(in: 0.4...1.8)).rounded())
    }

    private func todayBar(for symbol: String) -> Candle? {
        guard let quote = quotes[symbol], let open = sessionOpens[symbol] else { return nil }
        return Candle(time: Calendar.current.startOfDay(for: open), open: quote.open, high: quote.high, low: quote.low, close: quote.last, volume: quote.volume)
    }

    private func tradingDay(before date: Date, sessions: Int) -> Date {
        var result = date
        var remaining = sessions
        let calendar = Calendar.current
        while remaining > 0 {
            result = calendar.date(byAdding: .day, value: -1, to: result)!
            if !calendar.isDateInWeekend(result) {
                remaining -= 1
            }
        }
        return result
    }

    private func aggregate(_ bars: [Candle], bucket: (Date) -> Date) -> [Candle] {
        var result: [Candle] = []
        for bar in bars {
            let key = bucket(bar.time)
            if let last = result.last, last.time == key {
                result[result.count - 1].absorb(bar)
            } else {
                var copy = bar
                copy.time = key
                result.append(copy)
            }
        }
        return result
    }

    // MARK: Microstructure

    private func applySpread(to quote: inout Quote, instrument: Instrument) {
        guard instrument.isTradable else {
            quote.bid = quote.last
            quote.ask = quote.last
            return
        }
        let increment = priceIncrement(for: quote.last)
        let halfSpread = max(increment, (quote.last * 0.0001 / increment).rounded() * increment)
        quote.bid = roundToTick(quote.last - halfSpread / 2)
        quote.ask = roundToTick(quote.bid + halfSpread)
        quote.bidSize = rng.int(in: 1...30) * 100
        quote.askSize = rng.int(in: 1...30) * 100
    }

    private func lotSize(for instrument: Instrument) -> Int {
        let roll = rng.unit()
        if roll < 0.55 { return rng.int(in: 1...99) }
        if roll < 0.92 { return rng.int(in: 1...10) * 100 }
        return rng.int(in: 10...80) * 100
    }

    private func priceIncrement(for price: Double) -> Double {
        price >= 1_000 ? 0.05 : 0.01
    }

    private func roundToTick(_ price: Double) -> Double {
        (price * 100).rounded() / 100
    }
}
