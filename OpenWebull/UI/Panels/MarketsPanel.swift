import AppKit

/// Market overview: index cards, a sector heatmap and the three movers lists.
final class MarketsPanel: PanelViewController {
    private var cards: [IndexCardView] = []
    private let heatmap = SectorHeatmapView()

    init(env: AppEnvironment) {
        super.init(env: env, title: "Markets")
    }

    override func buildContent() {
        cards = InstrumentCatalog.indices.map { _ in IndexCardView() }
        cards.forEach { card in
            card.onClick = { [unowned self] symbol in env.link.select(symbol) }
        }
        let cardRow = NSStackView(views: cards)
        cardRow.distribution = .fillEqually
        cardRow.spacing = 10

        heatmap.onSelect = { [unowned self] symbol in env.link.select(symbol) }
        let heatmapTitle = sectionTitle("Sector Heatmap")

        let movers = [MoversPanel.Category.gainers, .losers, .mostActive].map { category in
            let panel = TabbedPanelController(panels: [MoversPanel(env: env, category: category, limit: 12)])
            addChild(panel)
            return panel.view
        }
        let moversRow = NSStackView(views: movers)
        moversRow.distribution = .fillEqually
        moversRow.spacing = 10

        view.addSubviews(cardRow, heatmapTitle, heatmap, moversRow)
        NSLayoutConstraint.activate([
            cardRow.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            cardRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            cardRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            cardRow.heightAnchor.constraint(equalToConstant: 110),
            heatmapTitle.topAnchor.constraint(equalTo: cardRow.bottomAnchor, constant: 16),
            heatmapTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            heatmap.topAnchor.constraint(equalTo: heatmapTitle.bottomAnchor, constant: 8),
            heatmap.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            heatmap.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            heatmap.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.34),
            moversRow.topAnchor.constraint(equalTo: heatmap.bottomAnchor, constant: 14),
            moversRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            moversRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            moversRow.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    override func refresh() {
        for (card, instrument) in zip(cards, InstrumentCatalog.indices) {
            guard let quote = env.market.quote(for: instrument.symbol) else { continue }
            card.update(instrument: instrument, quote: quote, closes: env.market.sessionCloses(for: instrument.symbol))
        }
        heatmap.tiles = env.market.instruments
            .filter { $0.kind == .stock }
            .compactMap { instrument in
                env.market.quote(for: instrument.symbol).map {
                    SectorHeatmapView.Tile(symbol: instrument.symbol, sector: instrument.sector, changePercent: $0.changePercent, weight: instrument.sharesOutstanding * $0.last)
                }
            }
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        .label(text, font: Theme.font(13, .semibold))
    }
}

final class IndexCardView: FillView {
    var onClick: ((String) -> Void)?

    private let nameLabel = NSTextField.label(font: Theme.font(11.5), color: Theme.textSecondary)
    private let levelLabel = NSTextField.label(font: Theme.numberFont(17, .semibold))
    private let changeLabel = NSTextField.label(font: Theme.numberFont(11.5, .medium))
    private let sparkline = SparklineView()
    private var symbol = ""

    init() {
        super.init(color: Theme.toolbarBackground)
        layer?.cornerRadius = 4
        addSubviews(nameLabel, levelLabel, changeLabel, sparkline)
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            levelLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            levelLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            changeLabel.topAnchor.constraint(equalTo: levelLabel.bottomAnchor, constant: 2),
            changeLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            sparkline.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            sparkline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            sparkline.topAnchor.constraint(equalTo: changeLabel.bottomAnchor, constant: 4),
            sparkline.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    func update(instrument: Instrument, quote: Quote, closes: [Double]) {
        symbol = instrument.symbol
        nameLabel.stringValue = instrument.name
        levelLabel.stringValue = Format.price(quote.last)
        let trend = Theme.trendColor(quote.change)
        changeLabel.stringValue = "\(Format.signedPrice(quote.change))  \(Format.percent(quote.changePercent))"
        changeLabel.textColor = trend
        sparkline.lineColor = trend
        sparkline.baseline = quote.previousClose
        sparkline.values = closes
    }

    override func mouseUp(with event: NSEvent) {
        onClick?(symbol)
    }
}

/// Sectors laid out as columns proportional to their total weight; each stock is a tile
/// sized by market cap and coloured by its daily change.
final class SectorHeatmapView: NSView {
    struct Tile {
        let symbol: String
        let sector: String
        let changePercent: Double
        let weight: Double
    }

    var tiles: [Tile] = [] {
        didSet { needsDisplay = true }
    }

    var onSelect: ((String) -> Void)?

    private var hitAreas: [(NSRect, String)] = []

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.panelBackground.setFill()
        bounds.fill()
        hitAreas = []
        let sectors = Dictionary(grouping: tiles, by: \.sector)
            .map { (name: $0.key, tiles: $0.value.sorted { $0.weight > $1.weight }) }
            .sorted { $0.tiles.reduce(0) { $0 + $1.weight } > $1.tiles.reduce(0) { $0 + $1.weight } }
        let totalWeight = tiles.reduce(0) { $0 + sqrt($1.weight) }
        guard totalWeight > 0 else { return }

        var x: CGFloat = 0
        for sector in sectors {
            let sectorWeight = sector.tiles.reduce(0) { $0 + sqrt($1.weight) }
            let width = bounds.width * CGFloat(sectorWeight / totalWeight)
            let column = NSRect(x: x, y: 0, width: width, height: bounds.height)
            drawLabel(sector.name.uppercased(), in: NSRect(x: column.minX + 4, y: 2, width: column.width - 8, height: 14), size: 9.5, color: Theme.textSecondary)
            var y: CGFloat = 16
            for tile in sector.tiles {
                let height = (bounds.height - 16) * CGFloat(sqrt(tile.weight) / sectorWeight)
                let rect = NSRect(x: column.minX + 1, y: y + 1, width: column.width - 2, height: height - 2)
                color(for: tile.changePercent).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
                if rect.height > 26, rect.width > 40 {
                    drawLabel(tile.symbol, in: NSRect(x: rect.minX, y: rect.midY - 13, width: rect.width, height: 14), size: 11.5, color: .white, weight: .bold)
                    drawLabel(Format.percent(tile.changePercent), in: NSRect(x: rect.minX, y: rect.midY + 1, width: rect.width, height: 13), size: 10, color: .white)
                } else if rect.height > 12 {
                    drawLabel(tile.symbol, in: NSRect(x: rect.minX, y: rect.midY - 6, width: rect.width, height: 12), size: 9, color: .white, weight: .semibold)
                }
                hitAreas.append((rect, tile.symbol))
                y += height
            }
            x += width
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = hitAreas.first(where: { $0.0.contains(point) }) {
            onSelect?(hit.1)
        }
    }

    private func color(for change: Double) -> NSColor {
        let intensity = min(abs(change) / 0.03, 1)
        let base = change >= 0 ? Theme.up : Theme.down
        return Theme.raisedBackground.blended(withFraction: 0.25 + 0.75 * intensity, of: base) ?? base
    }

    private func drawLabel(_ text: String, in rect: NSRect, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [
            .font: Theme.numberFont(size, weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
    }
}
