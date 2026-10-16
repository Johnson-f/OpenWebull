import AppKit

/// Side drawers opened from the right rail.
enum RailDrawer: Int, CaseIterable {
    case trade, positions, quotes, movers, news

    var title: String {
        switch self {
        case .trade: "Trade"
        case .positions: "Positions & Orders"
        case .quotes: "Level 2 & Time and Sales"
        case .movers: "Market Movers"
        case .news: "News Feed"
        }
    }

    var symbolName: String {
        switch self {
        case .trade: "dollarsign.circle.fill"
        case .positions: "briefcase.fill"
        case .quotes: "chart.bar.doc.horizontal.fill"
        case .movers: "globe.americas.fill"
        case .news: "envelope.fill"
        }
    }

    @MainActor
    func makePanels(env: AppEnvironment) -> [NSViewController] {
        switch self {
        case .trade: [OrderEntryPanel(env: env)]
        case .positions: [PositionsPanel(env: env), OrdersPanel(env: env)]
        case .quotes: [Level2Panel(env: env), TimeAndSalesPanel(env: env)]
        case .movers: [MoversPanel(env: env, category: .gainers), MoversPanel(env: env, category: .losers), MoversPanel(env: env, category: .mostActive)]
        case .news: [NewsPanel(env: env)]
        }
    }
}

final class RightRailView: FillView {
    static let width: CGFloat = 46

    var onToggleDrawer: ((RailDrawer) -> Void)?
    var onShowChart: (() -> Void)?
    var onHelp: (() -> Void)?
    var onSettings: (() -> Void)?

    private var drawerButtons: [RailDrawer: IconButton] = [:]
    private var chartButton: IconButton!

    init() {
        super.init(color: Theme.railBackground)
        chartButton = makeButton(symbol: "chart.line.uptrend.xyaxis", tooltip: "Chart", action: #selector(chartClicked))
        let top = NSStackView()
        top.orientation = .vertical
        top.spacing = 22
        for drawer in [RailDrawer.trade, .positions] {
            top.addArrangedSubview(drawerButton(drawer))
        }
        top.addArrangedSubview(chartButton)
        for drawer in [RailDrawer.quotes, .movers] {
            top.addArrangedSubview(drawerButton(drawer))
        }

        let bottom = NSStackView(views: [
            drawerButton(.news),
            makeButton(symbol: "questionmark.circle.fill", tooltip: "Help & Shortcuts", action: #selector(helpClicked)),
            makeButton(symbol: "gearshape.fill", tooltip: "Settings", action: #selector(settingsClicked)),
        ])
        bottom.orientation = .vertical
        bottom.spacing = 22

        addSubviews(top, bottom)
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            top.centerXAnchor.constraint(equalTo: centerXAnchor),
            bottom.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            bottom.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    func update(openDrawer: RailDrawer?, chartVisible: Bool) {
        for (drawer, button) in drawerButtons {
            button.isActive = drawer == openDrawer
        }
        chartButton.isActive = chartVisible && openDrawer == nil
    }

    private func drawerButton(_ drawer: RailDrawer) -> IconButton {
        let button = makeButton(symbol: drawer.symbolName, tooltip: drawer.title, action: #selector(drawerClicked(_:)))
        button.tag = drawer.rawValue
        drawerButtons[drawer] = button
        return button
    }

    private func makeButton(symbol: String, tooltip: String, action: Selector) -> IconButton {
        let button = IconButton(symbol: symbol, size: 18, tooltip: tooltip, target: self, action: action)
        button.inactiveTint = Theme.railIcon
        button.activeTint = Theme.railActive
        button.isActive = false
        return button
    }

    @objc private func drawerClicked(_ sender: NSButton) {
        guard let drawer = RailDrawer(rawValue: sender.tag) else { return }
        onToggleDrawer?(drawer)
    }

    @objc private func chartClicked() { onShowChart?() }
    @objc private func helpClicked() { onHelp?() }
    @objc private func settingsClicked() { onSettings?() }
}
