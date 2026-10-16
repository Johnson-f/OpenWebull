import AppKit

/// The Stocks page: research tabs for the linked symbol, opening on the chart.
final class StockPagePanel: PanelViewController {
    private var tabs: TabbedPanelController!

    init(env: AppEnvironment) {
        super.init(env: env, title: "Stocks")
    }

    override func buildContent() {
        let chart = ChartPanel(env: env)
        let panels: [NSViewController] = [
            CorporateActionsPanel(env: env),
            InstitutionsPanel(env: env),
            MessagesPanel(env: env),
            NewsPanel(env: env),
            OptionsChainPanel(env: env),
            chart,
            KeyStatsPanel(env: env, tabTitle: "Profile"),
            FinancialsPanel(env: env),
            QuotesPanel(env: env),
            SymbolPnLPanel(env: env),
            NotePanel(env: env),
            ReleasesPanel(env: env),
        ]
        tabs = TabbedPanelController(panels: panels, selectedIndex: panels.firstIndex { $0 === chart }!)
        chart.onShowNews = { [unowned self] in tabs.show(title: "News") }
        tabs.strip.trailingMenu = { [unowned self] in tabMenu() }
        addChild(tabs)
        view.addSubviews(tabs.view)
        tabs.view.pinEdges(to: view)
    }

    func showChart() {
        tabs.show(title: "Chart")
    }

    private func tabMenu() -> NSMenu {
        let menu = NSMenu()
        for (index, panel) in tabs.panels.enumerated() {
            let item = NSMenuItem(title: panel.title ?? "", action: #selector(selectTab(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            item.state = index == tabs.selectedIndex ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func selectTab(_ sender: NSMenuItem) {
        tabs.show(sender.tag)
    }
}
