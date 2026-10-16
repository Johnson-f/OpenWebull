import AppKit

/// Base class for every dockable panel. Subclasses build their views in `buildContent()`
/// and redraw in `refresh()`, which runs on every market tick while the panel is on screen.
class PanelViewController: NSViewController {
    let env: AppEnvironment

    init(env: AppEnvironment, title: String) {
        self.env = env
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var linkedSymbol: String { env.link.symbol }

    var isOnScreen: Bool {
        isViewLoaded && view.window != nil && !view.isHiddenOrHasHiddenAncestor
    }

    override func loadView() {
        view = FillView(color: Theme.panelBackground)
        buildContent()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        env.market.ticked.observe(self) { [weak self] in
            guard let self, self.isOnScreen else { return }
            self.marketDidTick()
        }
        env.link.changed.observe(self) { [weak self] symbol in
            guard let self, self.isViewLoaded else { return }
            self.linkedSymbolDidChange(symbol)
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    func buildContent() {}

    func refresh() {}

    func marketDidTick() {
        refresh()
    }

    func linkedSymbolDidChange(_ symbol: String) {
        refresh()
    }
}
