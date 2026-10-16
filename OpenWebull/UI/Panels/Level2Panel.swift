import AppKit

/// Bid and ask depth side by side, with size bars and a bid/ask imbalance gauge.
final class Level2Panel: PanelViewController {
    private let ladder = DepthLadderView()

    init(env: AppEnvironment) {
        super.init(env: env, title: "Level 2")
    }

    override func buildContent() {
        view.addSubviews(ladder)
        ladder.pinEdges(to: view)
        ladder.onPriceClick = { [unowned self] price in
            env.orderTicketPrice.send(price)
        }
    }

    override func refresh() {
        ladder.book = env.market.orderBook(for: linkedSymbol)
    }
}

final class DepthLadderView: NSView {
    var book: OrderBook? {
        didSet { needsDisplay = true }
    }

    var onPriceClick: ((Double) -> Void)?

    private let rowHeight: CGFloat = 20
    private let gaugeHeight: CGFloat = 26
    private let headerHeight: CGFloat = 20
    private let font = Theme.numberFont(11.5)
    private static let minimumSideWidthForVenue: CGFloat = 170

    private var showsVenue: Bool { bounds.width / 2 >= Self.minimumSideWidthForVenue }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.panelBackground.setFill()
        bounds.fill()
        guard let book, !book.bids.isEmpty else {
            draw("Depth is not available for this instrument.", in: bounds.insetBy(dx: 12, dy: 12), color: Theme.textTertiary, alignment: .left)
            return
        }
        drawGauge(book)
        let half = bounds.width / 2
        drawHeader(in: NSRect(x: 0, y: gaugeHeight, width: half, height: headerHeight), titles: ["Venue", "Bid", "Size"])
        drawHeader(in: NSRect(x: half, y: gaugeHeight, width: half, height: headerHeight), titles: ["Venue", "Ask", "Size"])
        let maxSize = Double((book.bids + book.asks).map(\.size).max() ?? 1)
        drawSide(book.bids, x: 0, width: half, maxSize: maxSize, color: Theme.up)
        drawSide(book.asks, x: half, width: half, maxSize: maxSize, color: Theme.down)
        Theme.separator.setFill()
        NSRect(x: half, y: gaugeHeight, width: 1, height: bounds.height - gaugeHeight).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard let book else { return }
        let point = convert(event.locationInWindow, from: nil)
        let row = Int((point.y - gaugeHeight - headerHeight) / rowHeight)
        let side = point.x < bounds.width / 2 ? book.bids : book.asks
        guard row >= 0, row < side.count else { return }
        onPriceClick?(side[row].price)
    }

    private func drawGauge(_ book: OrderBook) {
        let total = max(Double(book.totalBidSize + book.totalAskSize), 1)
        let bidFraction = Double(book.totalBidSize) / total
        let bar = NSRect(x: 8, y: 8, width: bounds.width - 16, height: 6)
        Theme.down.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()
        Theme.up.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: NSRect(x: bar.minX, y: bar.minY, width: bar.width * bidFraction, height: bar.height), xRadius: 3, yRadius: 3).fill()
        draw(String(format: "%.0f%%", bidFraction * 100), in: NSRect(x: 8, y: 14, width: 60, height: 12), color: Theme.up, alignment: .left, small: true)
        draw(String(format: "%.0f%%", (1 - bidFraction) * 100), in: NSRect(x: bounds.width - 68, y: 14, width: 60, height: 12), color: Theme.down, alignment: .right, small: true)
    }

    private func drawHeader(in rect: NSRect, titles: [String]) {
        Theme.panelHeader.setFill()
        rect.fill()
        for (index, frame) in columnFrames(in: rect).enumerated() where frame.width > 0 {
            draw(titles[index], in: frame, color: Theme.textSecondary, alignment: index == 0 ? .left : .right, small: true)
        }
    }

    private func drawSide(_ levels: [BookLevel], x: CGFloat, width: CGFloat, maxSize: Double, color: NSColor) {
        for (index, level) in levels.enumerated() {
            let rowRect = NSRect(x: x, y: gaugeHeight + headerHeight + CGFloat(index) * rowHeight, width: width, height: rowHeight)
            guard rowRect.minY < bounds.height else { break }
            let shade = max(0.04, 0.22 - Double(index) * 0.015)
            color.withAlphaComponent(shade).setFill()
            rowRect.fill()
            let barWidth = rowRect.width * CGFloat(Double(level.size) / maxSize)
            color.withAlphaComponent(0.18).setFill()
            NSRect(x: x == 0 ? rowRect.maxX - barWidth : rowRect.minX, y: rowRect.minY + 2, width: barWidth, height: rowRect.height - 4).fill()
            let frames = columnFrames(in: rowRect)
            if frames[0].width > 0 {
                draw(level.venue, in: frames[0], color: Theme.textSecondary, alignment: .left)
            }
            draw(Format.price(level.price), in: frames[1], color: color, alignment: .right)
            draw(Format.integer(level.size), in: frames[2], color: Theme.textPrimary, alignment: .right)
        }
    }

    private func columnFrames(in rect: NSRect) -> [NSRect] {
        let inset = rect.insetBy(dx: 6, dy: 0)
        let fractions: [CGFloat] = showsVenue ? [0.28, 0.38, 0.34] : [0, 0.55, 0.45]
        let widths = fractions.map { inset.width * $0 }
        var x = inset.minX
        return widths.map { width in
            defer { x += width }
            return NSRect(x: x, y: rect.minY, width: width, height: rect.height)
        }
    }

    private func draw(_ text: String, in rect: NSRect, color: NSColor, alignment: NSTextAlignment, small: Bool = false) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: small ? Theme.font(10.5) : font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let height = (text as NSString).size(withAttributes: attributes).height
        (text as NSString).draw(in: NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height), withAttributes: attributes)
    }
}
