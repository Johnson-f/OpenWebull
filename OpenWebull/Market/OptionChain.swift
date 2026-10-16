import Foundation

struct OptionContract: Sendable {
    enum Right: Sendable {
        case call, put
    }

    let right: Right
    let strike: Double
    let expiration: Date
    let bid: Double
    let ask: Double
    let last: Double
    let impliedVolatility: Double
    let delta: Double
    let gamma: Double
    let theta: Double
    let vega: Double
    let volume: Int
    let openInterest: Int

    var mid: Double { (bid + ask) / 2 }
}

struct OptionChainRow: Sendable {
    let strike: Double
    let call: OptionContract
    let put: OptionContract
}

enum OptionChainBuilder {
    static let riskFreeRate = 0.04

    static func expirations(from now: Date, count: Int = 8) -> [Date] {
        let calendar = Calendar.current
        var date = calendar.startOfDay(for: now)
        var result: [Date] = []
        while result.count < count {
            date = calendar.date(byAdding: .day, value: 1, to: date)!
            if calendar.component(.weekday, from: date) == 6 {
                result.append(date.addingTimeInterval(16 * 3600))
            }
        }
        return result
    }

    static func strikeIncrement(for spot: Double) -> Double {
        switch spot {
        case ..<25: 0.5
        case ..<100: 1
        case ..<250: 2.5
        case ..<1_000: 5
        default: 10
        }
    }

    static func chain(for instrument: Instrument, spot: Double, expiration: Date, now: Date, strikesEachSide: Int = 12) -> [OptionChainRow] {
        let increment = strikeIncrement(for: spot)
        let atm = (spot / increment).rounded() * increment
        let years = max(expiration.timeIntervalSince(now), 3600) / (365 * 86_400)
        var rng = SeededGenerator(string: "\(instrument.symbol)-\(Int(expiration.timeIntervalSince1970))")

        return (-strikesEachSide...strikesEachSide).compactMap { offset in
            let strike = atm + Double(offset) * increment
            guard strike > 0 else { return nil }
            let moneyness = log(strike / spot)
            let iv = instrument.volatility * (1 + 1.8 * moneyness * moneyness - 0.25 * moneyness)
            let activity = exp(-abs(Double(offset)) / 5)
            return OptionChainRow(
                strike: strike,
                call: contract(.call, spot: spot, strike: strike, years: years, iv: iv, expiration: expiration, activity: activity, rng: &rng),
                put: contract(.put, spot: spot, strike: strike, years: years, iv: iv, expiration: expiration, activity: activity, rng: &rng)
            )
        }
    }

    private static func contract(
        _ right: OptionContract.Right, spot: Double, strike: Double, years: Double, iv: Double,
        expiration: Date, activity: Double, rng: inout SeededGenerator
    ) -> OptionContract {
        let greeks = BlackScholes(spot: spot, strike: strike, years: years, rate: riskFreeRate, volatility: iv)
        let value = right == .call ? greeks.callPrice : greeks.putPrice
        let halfSpread = max(0.01, value * 0.02)
        let bid = max(0, ((value - halfSpread) * 100).rounded() / 100)
        let ask = max(0.01, ((value + halfSpread) * 100).rounded() / 100)
        return OptionContract(
            right: right, strike: strike, expiration: expiration,
            bid: bid, ask: ask, last: ((value + halfSpread * rng.double(in: -1...1)) * 100).rounded() / 100,
            impliedVolatility: iv,
            delta: right == .call ? greeks.callDelta : greeks.putDelta,
            gamma: greeks.gamma,
            theta: right == .call ? greeks.callTheta : greeks.putTheta,
            vega: greeks.vega,
            volume: Int(Double(rng.int(in: 50...9_000)) * activity),
            openInterest: Int(Double(rng.int(in: 500...60_000)) * activity)
        )
    }
}

struct BlackScholes {
    let spot: Double
    let strike: Double
    let years: Double
    let rate: Double
    let volatility: Double

    private var sqrtT: Double { sqrt(years) }
    private var d1: Double { (log(spot / strike) + (rate + volatility * volatility / 2) * years) / (volatility * sqrtT) }
    private var d2: Double { d1 - volatility * sqrtT }
    private var discount: Double { exp(-rate * years) }

    var callPrice: Double { spot * cdf(d1) - strike * discount * cdf(d2) }
    var putPrice: Double { strike * discount * cdf(-d2) - spot * cdf(-d1) }
    var callDelta: Double { cdf(d1) }
    var putDelta: Double { cdf(d1) - 1 }
    var gamma: Double { pdf(d1) / (spot * volatility * sqrtT) }
    /// Per 1 vol point.
    var vega: Double { spot * pdf(d1) * sqrtT / 100 }
    /// Per calendar day.
    var callTheta: Double { (-spot * pdf(d1) * volatility / (2 * sqrtT) - rate * strike * discount * cdf(d2)) / 365 }
    var putTheta: Double { (-spot * pdf(d1) * volatility / (2 * sqrtT) + rate * strike * discount * cdf(-d2)) / 365 }

    private func cdf(_ x: Double) -> Double { 0.5 * erfc(-x / sqrt(2)) }
    private func pdf(_ x: Double) -> Double { exp(-x * x / 2) / sqrt(2 * .pi) }
}
