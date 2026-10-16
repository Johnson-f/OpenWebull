import AppKit

enum PanelKind {
    case watchlist
    case watchlistDetailed
    case stockPage
    case alerts
    case chart
    case optionsChain
    case news
    case keyStats
    case level2
    case timeAndSales
    case orderEntry
    case positions
    case orders
    case movers(MoversPanel.Category)
    case markets
    case screener
    case account

    @MainActor
    func makePanel(env: AppEnvironment) -> PanelViewController {
        switch self {
        case .watchlist: WatchlistPanel(env: env, density: .compact)
        case .watchlistDetailed: WatchlistPanel(env: env, density: .detailed)
        case .stockPage: StockPagePanel(env: env)
        case .alerts: AlertsPanel(env: env)
        case .chart: ChartPanel(env: env)
        case .optionsChain: OptionsChainPanel(env: env)
        case .news: NewsPanel(env: env)
        case .keyStats: KeyStatsPanel(env: env)
        case .level2: Level2Panel(env: env)
        case .timeAndSales: TimeAndSalesPanel(env: env)
        case .orderEntry: OrderEntryPanel(env: env)
        case .positions: PositionsPanel(env: env)
        case .orders: OrdersPanel(env: env)
        case let .movers(category): MoversPanel(env: env, category: category)
        case .markets: MarketsPanel(env: env)
        case .screener: ScreenerPanel(env: env)
        case .account: AccountPanel(env: env)
        }
    }
}

/// A workspace is a tree of resizable splits whose leaves are tab groups of panels.
indirect enum LayoutNode {
    /// A single panel that supplies its own header, such as the tabbed Stocks page.
    case panel(PanelKind)
    case tabs([PanelKind])
    /// `weights` are relative initial sizes of the children along the split axis.
    case row([LayoutNode], weights: [CGFloat])
    case column([LayoutNode], weights: [CGFloat])
}

enum Workspace: Int, CaseIterable {
    case watchlists
    case stocks
    case markets
    case screener
    case account
    case dayTrader
    case swingTrader
    case optionsTrader
    case alerts

    static let toolbarPages: [Workspace] = [.stocks, .markets, .screener, .watchlists, .account, .dayTrader, .swingTrader, .optionsTrader, .alerts]

    /// Pages that sit beside the shared watchlist column; trader layouts carry their own.
    var showsSidebar: Bool {
        switch self {
        case .stocks, .markets, .screener, .account, .alerts: true
        case .watchlists, .dayTrader, .swingTrader, .optionsTrader: false
        }
    }

    var title: String {
        switch self {
        case .watchlists: "Watchlists"
        case .stocks: "Stocks"
        case .markets: "Markets"
        case .screener: "Screener"
        case .account: "Account"
        case .dayTrader: "Day Trader"
        case .swingTrader: "Swing Trader"
        case .optionsTrader: "Options"
        case .alerts: "Alerts"
        }
    }

    var symbolName: String {
        switch self {
        case .watchlists: "star.fill"
        case .stocks: "chart.xyaxis.line"
        case .markets: "gauge.with.dots.needle.67percent"
        case .screener: "line.3.horizontal.decrease.circle.fill"
        case .account: "tray.full.fill"
        case .dayTrader: "bolt.fill"
        case .swingTrader: "rectangle.split.3x1.fill"
        case .optionsTrader: "square.stack.3d.up.fill"
        case .alerts: "bell.fill"
        }
    }

    var layout: LayoutNode {
        switch self {
        case .watchlists:
            .row([
                .tabs([.watchlistDetailed]),
                .column([.tabs([.chart, .keyStats]), .tabs([.news])], weights: [0.6, 0.4]),
            ], weights: [0.58, 0.42])
        case .stocks:
            .panel(.stockPage)
        case .alerts:
            .tabs([.alerts])
        case .markets:
            .tabs([.markets])
        case .screener:
            .row([.tabs([.screener]), .tabs([.chart])], weights: [0.68, 0.32])
        case .account:
            .tabs([.account])
        case .dayTrader:
            .row([
                .tabs([.watchlist, .movers(.mostActive), .movers(.gainers)]),
                .column([
                    .tabs([.chart, .optionsChain]),
                    .tabs([.positions, .orders]),
                ], weights: [0.66, 0.34]),
                .column([.tabs([.level2]), .tabs([.orderEntry])], weights: [0.5, 0.5]),
                .tabs([.timeAndSales]),
            ], weights: [0.15, 0.5, 0.2, 0.15])
        case .swingTrader:
            .row([
                .tabs([.watchlist, .movers(.gainers), .movers(.losers)]),
                .column([.tabs([.chart]), .tabs([.news, .keyStats])], weights: [0.68, 0.32]),
                .column([.tabs([.orderEntry]), .tabs([.positions, .orders])], weights: [0.5, 0.5]),
            ], weights: [0.17, 0.55, 0.28])
        case .optionsTrader:
            .row([
                .column([.tabs([.optionsChain]), .tabs([.chart])], weights: [0.6, 0.4]),
                .column([.tabs([.orderEntry]), .tabs([.positions, .orders])], weights: [0.5, 0.5]),
            ], weights: [0.74, 0.26])
        }
    }
}

final class WorkspaceViewController: NSViewController {
    let workspace: Workspace
    private let env: AppEnvironment

    init(workspace: Workspace, env: AppEnvironment) {
        self.workspace = workspace
        self.env = env
        super.init(nibName: nil, bundle: nil)
        title = workspace.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = build(workspace.layout)
    }

    func showChart() {
        children.compactMap { $0 as? StockPagePanel }.first?.showChart()
    }

    private func build(_ node: LayoutNode) -> NSView {
        switch node {
        case let .panel(kind):
            let panel = kind.makePanel(env: env)
            addChild(panel)
            return panel.view
        case let .tabs(kinds):
            let tabs = TabbedPanelController(panels: kinds.map { $0.makePanel(env: env) })
            addChild(tabs)
            return tabs.view
        case let .row(children, weights):
            return WeightedSplitView(vertical: true, views: children.map(build), weights: weights)
        case let .column(children, weights):
            return WeightedSplitView(vertical: false, views: children.map(build), weights: weights)
        }
    }
}

/// An NSSplitView that applies proportional divider positions the first time it has a real size.
final class WeightedSplitView: NSSplitView, NSSplitViewDelegate {
    private let weights: [CGFloat]
    private var hasAppliedWeights = false
    private static let minimumPaneSize: CGFloat = 120

    init(vertical: Bool, views: [NSView], weights: [CGFloat]) {
        self.weights = weights
        super.init(frame: .zero)
        isVertical = vertical
        dividerStyle = .thin
        delegate = self
        views.forEach(addArrangedSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var dividerColor: NSColor { Theme.windowBackground }
    override var dividerThickness: CGFloat { 3 }

    override func layout() {
        super.layout()
        guard !hasAppliedWeights else { return }
        let length = isVertical ? bounds.width : bounds.height
        guard length > 0, weights.count == arrangedSubviews.count else { return }
        hasAppliedWeights = true
        let total = weights.reduce(0, +)
        let available = length - dividerThickness * CGFloat(weights.count - 1)
        var position: CGFloat = 0
        for index in 0..<(weights.count - 1) {
            position += available * weights[index] / total
            setPosition(position, ofDividerAt: index)
            position += dividerThickness
        }
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let origin = isVertical ? arrangedSubviews[dividerIndex].frame.minX : arrangedSubviews[dividerIndex].frame.minY
        return max(proposedMinimumPosition, origin + Self.minimumPaneSize)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let next = arrangedSubviews[dividerIndex + 1]
        let end = isVertical ? next.frame.maxX : next.frame.maxY
        return min(proposedMaximumPosition, end - Self.minimumPaneSize)
    }
}
