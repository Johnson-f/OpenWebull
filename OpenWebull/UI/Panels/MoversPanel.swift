import AppKit

/// Ranked lists of the simulated market: top gainers, top losers, or most active by volume.
final class MoversPanel: PanelViewController {
    enum Category: String {
        case gainers = "Top Gainers"
        case losers = "Top Losers"
        case mostActive = "Most Active"
    }

    private let category: Category
    private let limit: Int
    private var table: DataTableView!
    private var quotes: [Quote] = []

    init(env: AppEnvironment, category: Category, limit: Int = 15) {
        self.category = category
        self.limit = limit
        super.init(env: env, title: category.rawValue)
    }

    override func buildContent() {
        table = DataTableView(columns: [
            TableColumnSpec(id: "symbol", title: "Symbol", width: 120, alignment: .left),
            TableColumnSpec(id: "last", title: "Last", width: 70),
            TableColumnSpec(id: "metric", title: category == .mostActive ? "Volume" : "% Chg", width: 70),
        ], rowHeight: 36)
        table.rowCount = { [unowned self] in quotes.count }
        table.content = { [unowned self] row, column in cell(row: row, column: column) }
        table.onSelect = { [unowned self] row in env.link.select(quotes[row].symbol) }
        view.addSubviews(table)
        table.pinEdges(to: view)
    }

    override func refresh() {
        let tradable = env.market.instruments.filter(\.isTradable).compactMap { env.market.quote(for: $0.symbol) }
        let sorted: [Quote] = switch category {
        case .gainers: tradable.sorted { $0.changePercent > $1.changePercent }
        case .losers: tradable.sorted { $0.changePercent < $1.changePercent }
        case .mostActive: tradable.sorted { $0.volume * $0.last > $1.volume * $1.last }
        }
        quotes = Array(sorted.prefix(limit))
        table.tableView.reloadData()
    }

    private func cell(row: Int, column: String) -> CellContent {
        let quote = quotes[row]
        let trend = Theme.trendColor(quote.change)
        switch column {
        case "symbol": return .primary(quote.symbol, secondary: env.market.instrument(quote.symbol)?.name)
        case "last": return .number(Format.price(quote.last), color: trend)
        default:
            if category == .mostActive {
                return .number(Format.compact(quote.volume), color: Theme.textSecondary)
            }
            return .number(Format.percent(quote.changePercent), color: trend)
        }
    }
}
