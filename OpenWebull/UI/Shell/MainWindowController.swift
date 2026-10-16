import AppKit

/// Window layout: toolbar on top; watchlist column, page, optional drawer and icon rail in the
/// middle; status bar along the bottom.
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private static let lastWorkspaceKey = "lastWorkspace"
    private static let drawerWidth: CGFloat = 320

    private let env: AppEnvironment
    private let toolbar: TopToolbarView
    private let rail = RightRailView()
    private let statusBar = StatusBarView()
    private let sidebarHost = FillView(color: Theme.panelBackground)
    private let pageHost = FillView(color: Theme.panelBackground)
    private let drawerHost = FillView(color: Theme.panelBackground)
    private let rootController = NSViewController()
    private var sidebar: WatchlistSidebar!
    private var sidebarWidth: NSLayoutConstraint!
    private var sidebarDividerWidth: NSLayoutConstraint!
    private var drawerWidth: NSLayoutConstraint!
    private var pages: [Workspace: WorkspaceViewController] = [:]
    private var currentPage: WorkspaceViewController?
    private var drawers: [RailDrawer: TabbedPanelController] = [:]
    private var openDrawer: RailDrawer?
    private var toasts: ToastPresenter!

    init(env: AppEnvironment) {
        self.env = env
        toolbar = TopToolbarView(instruments: env.market.instruments)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1496, height: 940),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenWebull"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.windowBackground
        window.minSize = NSSize(width: 1100, height: 680)
        window.setFrameAutosaveName("MainWindow")
        super.init(window: window)
        window.delegate = self
        buildContent()
        if !window.setFrameUsingName("MainWindow") {
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(nil)
    }

    private func buildContent() {
        let root = FillView(color: Theme.windowBackground)
        let sidebarDivider = FillView(color: Theme.columnDivider)
        let drawerDivider = FillView(color: Theme.columnDivider)
        root.addSubviews(toolbar, sidebarHost, sidebarDivider, pageHost, drawerDivider, drawerHost, rail, statusBar)

        sidebarWidth = sidebarHost.widthAnchor.constraint(equalToConstant: WatchlistSidebar.width)
        drawerWidth = drawerHost.widthAnchor.constraint(equalToConstant: 0)
        sidebarDividerWidth = sidebarDivider.widthAnchor.constraint(equalToConstant: 4)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: TopToolbarView.height),

            sidebarHost.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            sidebarHost.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebarHost.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            sidebarWidth,
            sidebarDivider.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            sidebarDivider.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            sidebarDivider.leadingAnchor.constraint(equalTo: sidebarHost.trailingAnchor),
            sidebarDividerWidth,

            pageHost.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            pageHost.leadingAnchor.constraint(equalTo: sidebarDivider.trailingAnchor),
            pageHost.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            drawerDivider.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            drawerDivider.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            drawerDivider.leadingAnchor.constraint(equalTo: pageHost.trailingAnchor),
            drawerDivider.widthAnchor.constraint(equalToConstant: 1),
            drawerHost.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            drawerHost.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            drawerHost.leadingAnchor.constraint(equalTo: drawerDivider.trailingAnchor),
            drawerWidth,
            rail.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            rail.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            rail.leadingAnchor.constraint(equalTo: drawerHost.trailingAnchor),
            rail.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            rail.widthAnchor.constraint(equalToConstant: RightRailView.width),

            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: StatusBarView.height),
        ])
        drawerHost.clipsToBounds = true
        sidebarHost.clipsToBounds = true
        rootController.view = root
        window?.contentViewController = rootController
        toasts = ToastPresenter(host: root)

        sidebar = WatchlistSidebar(env: env)
        rootController.addChild(sidebar)
        sidebarHost.addSubview(sidebar.view)
        sidebar.view.pinEdges(to: sidebarHost)

        toolbar.onSelectPage = { [unowned self] workspace in show(workspace) }
        toolbar.onSymbolSearch = { [unowned self] symbol in
            env.link.select(symbol)
            show(.stocks)
            currentPage?.showChart()
        }
        toolbar.accountMenu = { [unowned self] in accountMenu() }
        rail.onToggleDrawer = { [unowned self] drawer in toggle(drawer) }
        rail.onShowChart = { [unowned self] in
            closeDrawer()
            show(.stocks)
            currentPage?.showChart()
        }
        rail.onHelp = { [unowned self] in showHelp() }
        rail.onSettings = { NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil) }
        statusBar.onRefresh = { [unowned self] in env.market.ticked.send() }

        env.market.ticked.observe(self) { [weak self] in self?.statusBar.update(now: Date()) }
        env.broker.orderFilled.observe(self) { [weak self] order in
            let side = order.ticket.side
            self?.toasts.show(
                "Filled: \(side.rawValue) \(order.ticket.quantity) \(order.symbol) @ \(Format.legendPrice(order.averageFillPrice ?? 0))",
                color: Theme.trendColor(side.sign)
            )
        }
        env.alerts.triggered.observe(self) { [weak self] alert in
            NSSound.beep()
            self?.toasts.show("Alert: \(alert.symbol) reached \(Format.legendPrice(alert.price))", color: Theme.accent)
        }

        let saved = (UserDefaults.standard.object(forKey: Self.lastWorkspaceKey) as? Int).flatMap(Workspace.init(rawValue:))
        show(saved ?? .stocks)
        statusBar.update(now: Date())
    }

    func show(_ workspace: Workspace) {
        let page = pages[workspace] ?? {
            let created = WorkspaceViewController(workspace: workspace, env: env)
            rootController.addChild(created)
            pages[workspace] = created
            return created
        }()
        if page !== currentPage {
            currentPage?.view.removeFromSuperview()
            pageHost.addSubview(page.view)
            page.view.pinEdges(to: pageHost)
            currentPage = page
        }
        sidebarWidth.constant = workspace.showsSidebar ? WatchlistSidebar.width : 0
        sidebarDividerWidth.constant = workspace.showsSidebar ? 4 : 0
        sidebar.view.isHidden = !workspace.showsSidebar
        toolbar.select(workspace)
        updateRail()
        UserDefaults.standard.set(workspace.rawValue, forKey: Self.lastWorkspaceKey)
    }

    func focusSearch() {
        window?.makeFirstResponder(toolbar.searchField)
    }

    // MARK: Drawers

    private func toggle(_ drawer: RailDrawer) {
        if openDrawer == drawer {
            closeDrawer()
            return
        }
        drawers[openDrawer ?? drawer]?.view.removeFromSuperview()
        let controller = drawers[drawer] ?? {
            let created = TabbedPanelController(panels: drawer.makePanels(env: env))
            rootController.addChild(created)
            drawers[drawer] = created
            return created
        }()
        drawerHost.addSubview(controller.view)
        controller.view.pinEdges(to: drawerHost)
        openDrawer = drawer
        drawerWidth.constant = Self.drawerWidth
        updateRail()
    }

    private func closeDrawer() {
        if let openDrawer { drawers[openDrawer]?.view.removeFromSuperview() }
        openDrawer = nil
        drawerWidth.constant = 0
        updateRail()
    }

    private func updateRail() {
        rail.update(openDrawer: openDrawer, chartVisible: currentPage?.workspace == .stocks)
    }

    // MARK: Menus

    private func accountMenu() -> NSMenu {
        let menu = NSMenu()
        let snapshot = env.broker.snapshot()
        let header = NSMenuItem(title: "Net Liquidation \(Format.currency(snapshot.netLiquidation)) · Day \(Format.signedCurrency(snapshot.dayPnL))", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let overview = NSMenuItem(title: "Account Overview", action: #selector(showAccount), keyEquivalent: "")
        overview.target = self
        menu.addItem(overview)
        let settings = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: "")
        menu.addItem(settings)
        return menu
    }

    @objc private func showAccount() {
        show(.account)
    }

    private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Shortcuts"
        alert.informativeText = """
        ⌘F  Search symbol
        ⌘1–⌘9  Switch page
        ⇧⌘K  Cancel all working orders
        Scroll  Zoom chart · Drag  Pan chart
        Click a Level 2 price to fill the order ticket.
        """
        alert.beginSheetModal(for: window!)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}
