import AppKit

/// Paper account overview: balance cards, an equity curve and positions/orders below.
final class AccountPanel: PanelViewController {
    private var cards: [String: (value: NSTextField, card: FillView)] = [:]
    private let equityCurve = SparklineView()
    private let curveTitle = NSTextField.label("Net Liquidation · 90 days", font: Theme.font(12, .semibold))
    private var history: [Double] = []

    private static let cardTitles = ["Net Liquidation", "Day P&L", "Unrealized P&L", "Realized P&L", "Cash", "Buying Power"]

    init(env: AppEnvironment) {
        super.init(env: env, title: "Account")
    }

    override func buildContent() {
        let cardViews = Self.cardTitles.map { title -> NSView in
            let card = FillView(color: Theme.panelHeader)
            card.layer?.cornerRadius = 6
            let caption = NSTextField.label(title, font: Theme.font(11.5), color: Theme.textSecondary)
            let value = NSTextField.label("--", font: Theme.numberFont(18, .semibold))
            card.addSubviews(caption, value)
            NSLayoutConstraint.activate([
                caption.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
                caption.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
                value.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 6),
                value.leadingAnchor.constraint(equalTo: caption.leadingAnchor),
                value.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -12),
                card.heightAnchor.constraint(equalToConstant: 72),
            ])
            cards[title] = (value, card)
            return card
        }
        let cardRow = NSStackView(views: cardViews)
        cardRow.distribution = .fillEqually
        cardRow.spacing = 10

        let resetButton = NSButton(title: "Reset Paper Account…", target: self, action: #selector(resetAccount))
        resetButton.controlSize = .small
        resetButton.translatesAutoresizingMaskIntoConstraints = false

        equityCurve.lineWidth = 2
        let curveBox = FillView(color: Theme.panelHeader)
        curveBox.layer?.cornerRadius = 6
        curveBox.addSubviews(curveTitle, equityCurve)

        let tabs = TabbedPanelController(panels: [PositionsPanel(env: env), OrdersPanel(env: env)])
        addChild(tabs)

        view.addSubviews(cardRow, curveBox, resetButton, tabs.view)
        NSLayoutConstraint.activate([
            cardRow.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            cardRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            cardRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            curveBox.topAnchor.constraint(equalTo: cardRow.bottomAnchor, constant: 12),
            curveBox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            curveBox.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            curveBox.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.3),
            curveTitle.topAnchor.constraint(equalTo: curveBox.topAnchor, constant: 10),
            curveTitle.leadingAnchor.constraint(equalTo: curveBox.leadingAnchor, constant: 12),
            resetButton.centerYAnchor.constraint(equalTo: curveTitle.centerYAnchor),
            resetButton.trailingAnchor.constraint(equalTo: curveBox.trailingAnchor, constant: -12),
            equityCurve.topAnchor.constraint(equalTo: curveTitle.bottomAnchor, constant: 8),
            equityCurve.leadingAnchor.constraint(equalTo: curveBox.leadingAnchor, constant: 10),
            equityCurve.trailingAnchor.constraint(equalTo: curveBox.trailingAnchor, constant: -10),
            equityCurve.bottomAnchor.constraint(equalTo: curveBox.bottomAnchor, constant: -10),
            tabs.view.topAnchor.constraint(equalTo: curveBox.bottomAnchor, constant: 12),
            tabs.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabs.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabs.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func refresh() {
        let snapshot = env.broker.snapshot()
        set("Net Liquidation", Format.currency(snapshot.netLiquidation), Theme.textPrimary)
        set("Day P&L", Format.signedCurrency(snapshot.dayPnL), Theme.trendColor(snapshot.dayPnL))
        set("Unrealized P&L", Format.signedCurrency(snapshot.unrealizedPnL), Theme.trendColor(snapshot.unrealizedPnL))
        set("Realized P&L", Format.signedCurrency(snapshot.realizedPnL), Theme.trendColor(snapshot.realizedPnL))
        set("Cash", Format.currency(snapshot.cash), Theme.textPrimary)
        set("Buying Power", Format.currency(snapshot.buyingPower), Theme.textPrimary)

        if history.isEmpty {
            history = Self.syntheticHistory(endingAt: snapshot.netLiquidation)
        }
        history[history.count - 1] = snapshot.netLiquidation
        equityCurve.values = history
        equityCurve.lineColor = Theme.trendColor(snapshot.netLiquidation - (history.first ?? 0))
    }

    private func set(_ title: String, _ text: String, _ color: NSColor) {
        cards[title]?.value.stringValue = text
        cards[title]?.value.textColor = color
    }

    /// A seeded random walk that lands on today's equity, standing in for account history.
    static func syntheticHistory(endingAt equity: Double, days: Int = 90) -> [Double] {
        var rng = SeededGenerator(string: "account-history")
        var values = [equity]
        for _ in 1..<days {
            values.append(values.last! / exp(0.012 * rng.gaussian() + 0.0008))
        }
        return values.reversed()
    }

    @objc private func resetAccount() {
        let alert = NSAlert()
        alert.messageText = "Reset the paper account?"
        alert.informativeText = "All positions and order history will be cleared and cash reset to $100,000."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.env.broker.reset()
            self.history = []
            self.refresh()
        }
    }
}
