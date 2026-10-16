import AppKit

struct ChartDrawing {
    enum Kind {
        case trendLine, horizontalLine
    }

    var kind: Kind
    var start: (time: Date, price: Double)
    var end: (time: Date, price: Double)
}

/// The price chart: candles, moving averages, a volume pane with its own average,
/// axis price tags, high/low markers, watermark, crosshair and simple drawing tools.
final class CandleChartView: NSView {
    enum Style: String, CaseIterable {
        case candles = "Candles"
        case hollow = "Hollow Candles"
        case bars = "OHLC Bars"
        case line = "Line"
        case area = "Area"
    }

    enum Tool {
        case none, trendLine, horizontalLine
    }

    static let movingAveragePeriods = [5, 10, 20, 60]
    static let volumeAveragePeriod = 20
    /// Space above the plot reserved for the legend chip, OHLC line and indicator line.
    static let legendHeight: CGFloat = 84

    var candles: [Candle] = [] {
        didSet {
            recomputeIndicators()
            needsDisplay = true
        }
    }

    var interval: ChartInterval = .fiveMinutes { didSet { needsDisplay = true } }
    var symbol = "" { didSet { needsDisplay = true } }
    var style: Style = .candles { didSet { needsDisplay = true } }
    var showsVolume = true { didSet { needsDisplay = true } }
    var showsMovingAverages = true { didSet { needsDisplay = true } }
    var showsDrawings = true { didSet { needsDisplay = true } }
    var snapsToPrices = true
    var autoScale = true { didSet { frozenRange = nil; needsDisplay = true } }
    /// Empty slots after the last bar, used to show the rest of the trading session.
    var trailingEmptySlots = 0 { didSet { needsDisplay = true } }
    /// Time left until the current bar closes, drawn under the last-price tag.
    var countdown: String? { didSet { needsDisplay = true } }
    var tool: Tool = .none {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    var drawings: [ChartDrawing] = [] { didSet { needsDisplay = true } }
    var onDrawingsChanged: (([ChartDrawing]) -> Void)?
    var onToolFinished: (() -> Void)?

    private var averages: [[Double?]] = []
    private var volumeAverage: [Double?] = []
    private(set) var visibleCount = 96
    private var rightOffset = 0
    private var crosshair: NSPoint?
    private var dragAnchor: (x: CGFloat, offset: Int)?
    private var pendingDrawing: ChartDrawing?
    private var frozenRange: (low: Double, high: Double)?
    private var indicatorsExpanded = true
    private var indicatorToggleRect = NSRect.zero

    private let axisWidth: CGFloat = 62
    private let timeAxisHeight: CGFloat = 24
    private let labelFont = Theme.numberFont(12)
    private let legendFont = Theme.numberFont(13)

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        (tool == .none ? NSCursor.arrow : NSCursor.crosshair).set()
    }

    // MARK: Viewport

    func setVisibleBars(_ count: Int) {
        visibleCount = max(10, count)
        rightOffset = 0
        frozenRange = nil
        needsDisplay = true
    }

    private var visibleRange: Range<Int> {
        let end = max(candles.count - rightOffset, 0)
        let barsShown = rightOffset == 0 ? max(visibleCount - trailingEmptySlots, 10) : visibleCount
        return max(0, end - barsShown)..<end
    }

    private func clampedOffset(_ offset: Int) -> Int {
        min(max(offset, 0), max(candles.count - 10, 0))
    }

    private func clampedCount(_ count: Int) -> Int {
        min(max(count, 20), max(candles.count + trailingEmptySlots, 20))
    }

    // MARK: Interaction

    override func mouseMoved(with event: NSEvent) {
        crosshair = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        crosshair = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if indicatorToggleRect.contains(point) {
            indicatorsExpanded.toggle()
            needsDisplay = true
            return
        }
        guard tool != .none, let anchor = chartPoint(at: point) else {
            dragAnchor = (point.x, rightOffset)
            return
        }
        let kind: ChartDrawing.Kind = tool == .trendLine ? .trendLine : .horizontalLine
        pendingDrawing = ChartDrawing(kind: kind, start: anchor, end: anchor)
        if kind == .horizontalLine {
            commitPendingDrawing()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        crosshair = location
        if pendingDrawing != nil, let point = chartPoint(at: location) {
            pendingDrawing?.end = point
        } else if let anchor = dragAnchor {
            rightOffset = clampedOffset(anchor.offset + Int((location.x - anchor.x) / max(slotWidth, 1)))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragAnchor = nil
        if pendingDrawing != nil {
            commitPendingDrawing()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX / 6 : event.scrollingDeltaX
            rightOffset = clampedOffset(rightOffset + Int(step.rounded()))
        } else {
            visibleCount = clampedCount(Int((CGFloat(visibleCount) * (event.scrollingDeltaY > 0 ? 0.9 : 1.1)).rounded()))
        }
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        visibleCount = clampedCount(Int((CGFloat(visibleCount) * (1 - event.magnification)).rounded()))
        needsDisplay = true
    }

    private func commitPendingDrawing() {
        guard let drawing = pendingDrawing else { return }
        pendingDrawing = nil
        drawings.append(drawing)
        onDrawingsChanged?(drawings)
        tool = .none
        onToolFinished?()
    }

    // MARK: Geometry

    private var plotRect: NSRect {
        NSRect(x: 0, y: 0, width: bounds.width - axisWidth, height: bounds.height - timeAxisHeight)
    }

    private var volumeTop: CGFloat {
        showsVolume ? plotRect.height * 0.8 : plotRect.maxY
    }

    private var priceRect: NSRect {
        NSRect(x: 0, y: Self.legendHeight, width: plotRect.width, height: volumeTop - Self.legendHeight - 10)
    }

    private var volumeRect: NSRect {
        NSRect(x: 0, y: volumeTop, width: plotRect.width, height: plotRect.maxY - volumeTop)
    }

    private var slotWidth: CGFloat {
        plotRect.width / CGFloat(max(visibleCount, 1))
    }

    private func x(forIndex index: Double, range: Range<Int>) -> CGFloat {
        plotRect.minX + (CGFloat(index - Double(range.lowerBound)) + 0.5) * slotWidth
    }

    private func priceBounds(range: Range<Int>) -> (low: Double, high: Double) {
        if !autoScale, let frozenRange { return frozenRange }
        var low = candles[range].map(\.low).min() ?? 0
        var high = candles[range].map(\.high).max() ?? 1
        if showsMovingAverages {
            for values in averages {
                for index in range {
                    if let value = values[index] {
                        low = min(low, value)
                        high = max(high, value)
                    }
                }
            }
        }
        let padding = max((high - low) * 0.06, high * 0.0005)
        let result = (low - padding, high + padding)
        if !autoScale { frozenRange = result }
        return result
    }

    private func y(_ price: Double, low: Double, high: Double) -> CGFloat {
        priceRect.minY + CGFloat((high - price) / max(high - low, .ulpOfOne)) * priceRect.height
    }

    /// Converts a point to a (time, price) anchor, snapping to the nearest OHLC value when enabled.
    private func chartPoint(at point: NSPoint) -> (time: Date, price: Double)? {
        let range = visibleRange
        guard !range.isEmpty, priceRect.contains(point) else { return nil }
        let (low, high) = priceBounds(range: range)
        let index = min(max(range.lowerBound + Int((point.x - plotRect.minX) / slotWidth), range.lowerBound), range.upperBound - 1)
        var price = high - Double((point.y - priceRect.minY) / priceRect.height) * (high - low)
        if snapsToPrices {
            let candle = candles[index]
            price = [candle.open, candle.high, candle.low, candle.close].min { abs($0 - price) < abs($1 - price) } ?? price
        }
        return (candles[index].time, price)
    }

    private func fractionalIndex(for time: Date) -> Double {
        guard let first = candles.first, let last = candles.last else { return 0 }
        if time <= first.time { return 0 }
        if time >= last.time { return Double(candles.count - 1) + time.timeIntervalSince(last.time) / interval.seconds }
        var lower = 0
        var upper = candles.count - 1
        while upper - lower > 1 {
            let mid = (lower + upper) / 2
            if candles[mid].time <= time { lower = mid } else { upper = mid }
        }
        let span = candles[upper].time.timeIntervalSince(candles[lower].time)
        return Double(lower) + (span > 0 ? time.timeIntervalSince(candles[lower].time) / span : 0)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        Theme.panelBackground.setFill()
        bounds.fill()
        let range = visibleRange
        guard !range.isEmpty, priceRect.height > 30 else { return }
        let (low, high) = priceBounds(range: range)
        let yFor: (Double) -> CGFloat = { [unowned self] in y($0, low: low, high: high) }

        drawWatermark()
        drawPriceAxis(low: low, high: high, yFor: yFor)
        drawTimeAxis(range: range)
        if showsVolume { drawVolume(range: range) }
        drawSeries(range: range, yFor: yFor)
        if showsMovingAverages { drawAverages(range: range, yFor: yFor) }
        drawHighLowMarkers(range: range, yFor: yFor)
        if showsDrawings { drawUserDrawings(range: range, yFor: yFor) }
        drawLastPriceLine(yFor: yFor)
        drawAxisTags(yFor: yFor)
        drawCrosshair(range: range, low: low, high: high)
        drawLegend(range: range)
    }

    private func drawWatermark() {
        let text = "\(symbol), \(interval.title)" as NSString
        let size = min(priceRect.height * 0.3, priceRect.width / CGFloat(max(text.length, 1)) * 1.7)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size), .foregroundColor: Theme.watermark]
        let measured = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: priceRect.midX - measured.width / 2, y: priceRect.midY - measured.height / 2), withAttributes: attributes)
    }

    private func drawPriceAxis(low: Double, high: Double, yFor: (Double) -> CGFloat) {
        let step = Self.niceStep(for: (high - low) / 9)
        let decimals = step < 0.01 ? 3 : (step < 10 ? 2 : 0)
        var level = (low / step).rounded(.up) * step
        while level < high {
            let lineY = yFor(level)
            if lineY > priceRect.minY + 4 {
                text(String(format: "%.\(decimals)f", level), at: NSPoint(x: plotRect.maxX + 8, y: lineY - 8), color: Theme.axisText, font: labelFont)
            }
            level += step
        }
    }

    private func drawTimeAxis(range: Range<Int>) {
        let minimumSpacing: CGFloat = 80
        var lastLabelX = -CGFloat.greatestFiniteMagnitude
        let calendar = Calendar.current
        let slots = range.lowerBound..<(range.upperBound + (rightOffset == 0 ? trailingEmptySlots : 0))
        var previous: Date?
        for slot in slots {
            let date = time(forSlot: slot)
            defer { previous = date }
            guard let previous, isMajorBoundary(previous: previous, current: date, calendar: calendar) else { continue }
            let labelX = x(forIndex: Double(slot), range: range)
            guard labelX - lastLabelX >= minimumSpacing, labelX > 24, labelX < plotRect.maxX - 24 else { continue }
            lastLabelX = labelX
            let label = timeLabel(previous: previous, current: date, calendar: calendar) as NSString
            let width = label.size(withAttributes: [.font: labelFont]).width
            text(label as String, at: NSPoint(x: labelX - width / 2, y: plotRect.maxY + 5), color: Theme.axisText, font: labelFont)
        }
    }

    private func time(forSlot slot: Int) -> Date {
        if slot < candles.count { return candles[slot].time }
        let last = candles.last?.time ?? Date()
        return last.addingTimeInterval(Double(slot - candles.count + 1) * interval.seconds)
    }

    private func isMajorBoundary(previous: Date, current: Date, calendar: Calendar) -> Bool {
        let newDay = !calendar.isDate(previous, inSameDayAs: current)
        let previousHour = calendar.component(.hour, from: previous)
        let hour = calendar.component(.hour, from: current)
        switch interval {
        case .oneMinute:
            return newDay || calendar.component(.minute, from: current) % 15 == 0
        case .fiveMinutes:
            return newDay || hour != previousHour
        case .fifteenMinutes, .thirtyMinutes, .oneHour:
            return newDay || (hour != previousHour && hour % 2 == 0)
        case .day:
            return calendar.component(.month, from: previous) != calendar.component(.month, from: current)
        case .week:
            let month = calendar.component(.month, from: current)
            return calendar.component(.month, from: previous) != month && month % 3 == 1
        case .month:
            return calendar.component(.year, from: previous) != calendar.component(.year, from: current)
        }
    }

    private func timeLabel(previous: Date, current: Date, calendar: Calendar) -> String {
        if interval.isIntraday {
            if !calendar.isDate(previous, inSameDayAs: current) { return "\(calendar.component(.day, from: current))" }
            return Self.formatter("HH:mm").string(from: current)
        }
        if calendar.component(.year, from: previous) != calendar.component(.year, from: current) {
            return Self.formatter("yyyy").string(from: current)
        }
        return Self.formatter("MMM").string(from: current)
    }

    private func drawSeries(range: Range<Int>, yFor: (Double) -> CGFloat) {
        let bodyWidth = max(1, slotWidth * 0.62)
        switch style {
        case .candles, .hollow:
            for index in range {
                let candle = candles[index]
                let isUp = candle.close >= candle.open
                let color = isUp ? Theme.candleUp : Theme.candleDown
                let centerX = x(forIndex: Double(index), range: range)
                color.setFill()
                NSRect(x: centerX - 0.5, y: yFor(candle.high), width: 1, height: max(1, yFor(candle.low) - yFor(candle.high))).fill()
                let top = yFor(max(candle.open, candle.close))
                let body = NSRect(x: centerX - bodyWidth / 2, y: top, width: bodyWidth, height: max(1, yFor(min(candle.open, candle.close)) - top))
                if style == .hollow, isUp, body.width > 3 {
                    Theme.panelBackground.setFill()
                    body.fill()
                    color.setStroke()
                    NSBezierPath(rect: body.insetBy(dx: 0.5, dy: 0.5)).stroke()
                } else {
                    body.fill()
                }
            }
        case .bars:
            for index in range {
                let candle = candles[index]
                (candle.close >= candle.open ? Theme.candleUp : Theme.candleDown).setFill()
                let centerX = x(forIndex: Double(index), range: range)
                let tick = max(2, bodyWidth / 2)
                NSRect(x: centerX - 0.5, y: yFor(candle.high), width: 1, height: max(1, yFor(candle.low) - yFor(candle.high))).fill()
                NSRect(x: centerX - tick, y: yFor(candle.open) - 0.5, width: tick, height: 1).fill()
                NSRect(x: centerX, y: yFor(candle.close) - 0.5, width: tick, height: 1).fill()
            }
        case .line, .area:
            let path = NSBezierPath()
            for index in range {
                let point = NSPoint(x: x(forIndex: Double(index), range: range), y: yFor(candles[index].close))
                index == range.lowerBound ? path.move(to: point) : path.line(to: point)
            }
            if style == .area {
                let fill = path.copy() as! NSBezierPath
                fill.line(to: NSPoint(x: x(forIndex: Double(range.upperBound - 1), range: range), y: priceRect.maxY))
                fill.line(to: NSPoint(x: x(forIndex: Double(range.lowerBound), range: range), y: priceRect.maxY))
                fill.close()
                NSGradient(starting: Theme.accent.withAlphaComponent(0.35), ending: Theme.accent.withAlphaComponent(0.02))?.draw(in: fill, angle: -90)
            }
            path.lineWidth = 1.5
            Theme.accent.setStroke()
            path.stroke()
        }
    }

    private func drawAverages(range: Range<Int>, yFor: (Double) -> CGFloat) {
        for (offset, values) in averages.enumerated() {
            let path = NSBezierPath()
            var started = false
            for bar in range {
                guard let value = values[bar] else { continue }
                let point = NSPoint(x: x(forIndex: Double(bar), range: range), y: yFor(value))
                started ? path.line(to: point) : path.move(to: point)
                started = true
            }
            path.lineWidth = 1.5
            path.lineJoinStyle = .round
            Theme.movingAverageColors[offset].setStroke()
            path.stroke()
        }
    }

    private func drawVolume(range: Range<Int>) {
        let rect = volumeRect
        Theme.separator.setFill()
        NSRect(x: 0, y: rect.minY, width: bounds.width, height: 1).fill()
        let bars = NSRect(x: rect.minX, y: rect.minY + 34, width: rect.width, height: rect.height - 36)
        guard bars.height > 10, let maxVolume = candles[range].map(\.volume).max(), maxVolume > 0 else { return }
        let bodyWidth = max(1, slotWidth * 0.62)
        let yForVolume: (Double) -> CGFloat = { bars.maxY - bars.height * CGFloat($0 / maxVolume) }
        for index in range {
            let candle = candles[index]
            (candle.close >= candle.open ? Theme.volumeUp : Theme.volumeDown).setFill()
            let top = yForVolume(candle.volume)
            NSRect(x: x(forIndex: Double(index), range: range) - bodyWidth / 2, y: top, width: bodyWidth, height: bars.maxY - top).fill()
        }
        let path = NSBezierPath()
        var started = false
        for index in range {
            guard let value = volumeAverage[index] else { continue }
            let point = NSPoint(x: x(forIndex: Double(index), range: range), y: yForVolume(value))
            started ? path.line(to: point) : path.move(to: point)
            started = true
        }
        path.lineWidth = 1
        Theme.volumeAverage.setStroke()
        path.stroke()

        for fraction in [1.0, 2.0 / 3, 1.0 / 3] {
            let value = maxVolume * fraction
            text(Format.compact(value), at: NSPoint(x: plotRect.maxX + 8, y: yForVolume(value) - 8), color: Theme.axisText, font: labelFont)
        }
        let index = hoveredIndex(range: range) ?? range.upperBound - 1
        var cursor = legendItem("VOL(\(Self.volumeAveragePeriod))", at: 14, y: rect.minY + 10, color: Theme.textPrimary, spacing: 8)
        cursor = legendItem("VOL \(Format.compact(candles[index].volume))", at: cursor, y: rect.minY + 10, color: Theme.volumeDown, spacing: 14)
        legendItem("VMA \(volumeAverage[index].map(Format.compact) ?? "--")", at: cursor, y: rect.minY + 10, color: Theme.volumeAverage, spacing: 0)
        if let lastAverage = volumeAverage[range.upperBound - 1] {
            tag(Format.compact(lastAverage), y: yForVolume(lastAverage), fill: Theme.volumeAverage, textColor: .white)
        }
    }

    private func drawHighLowMarkers(range: Range<Int>, yFor: (Double) -> CGFloat) {
        guard let highIndex = range.max(by: { candles[$0].high < candles[$1].high }),
              let lowIndex = range.min(by: { candles[$0].low < candles[$1].low }) else { return }
        marker(Format.legendPrice(candles[highIndex].high), index: highIndex, y: yFor(candles[highIndex].high), range: range, above: true)
        marker(Format.legendPrice(candles[lowIndex].low), index: lowIndex, y: yFor(candles[lowIndex].low), range: range, above: false)
    }

    private func marker(_ label: String, index: Int, y: CGFloat, range: Range<Int>, above: Bool) {
        let barX = x(forIndex: Double(index), range: range)
        let attributes: [NSAttributedString.Key: Any] = [.font: Theme.numberFont(11.5), .foregroundColor: Theme.axisText]
        let size = (label as NSString).size(withAttributes: attributes)
        let lineY = above ? y - 6 : y + 6
        let pointsLeft = barX > plotRect.midX
        let lineStart = pointsLeft ? barX - 26 : barX + 26
        Theme.axisText.setFill()
        NSRect(x: min(lineStart, barX), y: lineY, width: abs(barX - lineStart), height: 1).fill()
        NSRect(x: barX, y: min(lineY, y), width: 1, height: abs(y - lineY)).fill()
        NSBezierPath(ovalIn: NSRect(x: lineStart - 2, y: lineY - 1.5, width: 4, height: 4)).fill()
        let textX = pointsLeft ? lineStart - size.width - 4 : lineStart + 4
        (label as NSString).draw(at: NSPoint(x: textX, y: lineY - size.height / 2), withAttributes: attributes)
    }

    private func drawUserDrawings(range: Range<Int>, yFor: (Double) -> CGFloat) {
        for drawing in drawings + (pendingDrawing.map { [$0] } ?? []) {
            let path = NSBezierPath()
            switch drawing.kind {
            case .horizontalLine:
                let lineY = yFor(drawing.start.price)
                path.move(to: NSPoint(x: plotRect.minX, y: lineY))
                path.line(to: NSPoint(x: plotRect.maxX, y: lineY))
                tag(Format.legendPrice(drawing.start.price), y: lineY, fill: Theme.accent, textColor: .white)
            case .trendLine:
                let start = NSPoint(x: x(forIndex: fractionalIndex(for: drawing.start.time), range: range), y: yFor(drawing.start.price))
                let end = NSPoint(x: x(forIndex: fractionalIndex(for: drawing.end.time), range: range), y: yFor(drawing.end.price))
                path.move(to: start)
                path.line(to: end)
                Theme.accent.setFill()
                for point in [start, end] {
                    NSBezierPath(ovalIn: NSRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)).fill()
                }
            }
            path.lineWidth = 1.5
            Theme.accent.setStroke()
            path.stroke()
        }
    }

    private func drawLastPriceLine(yFor: (Double) -> CGFloat) {
        guard let last = candles.last else { return }
        let lineY = yFor(last.close)
        guard lineY >= priceRect.minY, lineY <= priceRect.maxY else { return }
        let path = NSBezierPath()
        path.move(to: NSPoint(x: plotRect.minX, y: lineY))
        path.line(to: NSPoint(x: plotRect.maxX, y: lineY))
        path.setLineDash([1, 2], count: 2, phase: 0)
        path.lineWidth = 1
        NSColor(hex: 0x6A6A6A).setStroke()
        path.stroke()
    }

    private func drawAxisTags(yFor: (Double) -> CGFloat) {
        guard let last = candles.last else { return }
        if showsMovingAverages {
            for (offset, values) in averages.enumerated().reversed() {
                guard let value = values[candles.count - 1] else { continue }
                tag(Format.legendPrice(value), y: yFor(value), fill: Theme.movingAverageColors[offset], textColor: .black)
            }
        }
        let lastY = yFor(last.close)
        tag(Format.legendPrice(last.close), y: lastY, fill: .white, textColor: .black)
        if let countdown {
            tag(countdown, y: lastY + 19, fill: Theme.countdownBackground, textColor: .white)
        }
    }

    private func drawCrosshair(range: Range<Int>, low: Double, high: Double) {
        guard let point = crosshair, plotRect.contains(point) else { return }
        let vertical = NSBezierPath()
        vertical.move(to: NSPoint(x: point.x, y: plotRect.minY))
        vertical.line(to: NSPoint(x: point.x, y: plotRect.maxY))
        let horizontal = NSBezierPath()
        horizontal.move(to: NSPoint(x: plotRect.minX, y: point.y))
        horizontal.line(to: NSPoint(x: plotRect.maxX, y: point.y))
        for path in [vertical, horizontal] {
            path.setLineDash([3, 3], count: 2, phase: 0)
            path.lineWidth = 1
            NSColor(hex: 0x8A8A8A).setStroke()
            path.stroke()
        }
        if priceRect.contains(point) {
            let price = high - Double((point.y - priceRect.minY) / priceRect.height) * (high - low)
            tag(Format.legendPrice(price), y: point.y, fill: Theme.tabSelectedBackground, textColor: Theme.textPrimary)
        }
        if let index = hoveredIndex(range: range) {
            let label = Self.formatter(interval.isIntraday ? "MM/dd HH:mm" : "yyyy/MM/dd").string(from: candles[index].time) as NSString
            let size = label.size(withAttributes: [.font: labelFont])
            let rect = NSRect(x: point.x - size.width / 2 - 5, y: plotRect.maxY + 2, width: size.width + 10, height: timeAxisHeight - 4)
            Theme.tabSelectedBackground.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            text(label as String, at: NSPoint(x: rect.minX + 5, y: rect.minY + 2), color: Theme.textPrimary, font: labelFont)
        }
    }

    private func drawLegend(range: Range<Int>) {
        let index = hoveredIndex(range: range) ?? range.upperBound - 1
        let candle = candles[index]
        let previousClose = index > 0 ? candles[index - 1].close : candle.open
        var cursor: CGFloat = 14
        let lineY: CGFloat = 40
        for (title, value) in [("O", candle.open), ("H", candle.high), ("L", candle.low), ("C", candle.close)] {
            cursor = legendItem("\(title) \(Format.legendPrice(value))", at: cursor, y: lineY, color: Theme.trendColor(value - previousClose), spacing: 12)
        }
        let change = candle.close - previousClose
        let percent = previousClose == 0 ? 0 : change / previousClose
        cursor = legendItem("\(Format.signedLegendPrice(change)) (\(Format.percent(percent)))", at: cursor, y: lineY, color: Theme.trendColor(change), spacing: 18)
        legendItem("Vol \(Format.integer(Int(candle.volume)))", at: cursor, y: lineY, color: Theme.textPrimary, spacing: 0)

        let indicatorY: CGFloat = 62
        indicatorToggleRect = NSRect(x: 8, y: indicatorY - 4, width: 22, height: 20)
        cursor = legendItem(indicatorsExpanded ? "⌄" : "›", at: 14, y: indicatorY - 2, color: Theme.textSecondary, spacing: 8)
        guard showsMovingAverages else { return }
        if indicatorsExpanded {
            for (offset, values) in averages.enumerated() {
                let label = "MA\(Self.movingAveragePeriods[offset]) \(values[index].map(Format.legendPrice) ?? "--")"
                cursor = legendItem(label, at: cursor, y: indicatorY, color: Theme.movingAverageColors[offset], spacing: 12, font: Theme.numberFont(12))
            }
        } else {
            legendItem("\(averages.count)", at: cursor, y: indicatorY, color: Theme.textSecondary, spacing: 0, font: Theme.numberFont(12))
        }
    }

    @discardableResult
    private func legendItem(_ string: String, at x: CGFloat, y: CGFloat, color: NSColor, spacing: CGFloat, font: NSFont? = nil) -> CGFloat {
        let font = font ?? legendFont
        text(string, at: NSPoint(x: x, y: y), color: color, font: font)
        return x + (string as NSString).size(withAttributes: [.font: font]).width + spacing
    }

    private func tag(_ string: String, y: CGFloat, fill: NSColor, textColor: NSColor) {
        let rect = NSRect(x: plotRect.maxX + 2, y: y - 9, width: axisWidth - 4, height: 18)
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        text(string, at: NSPoint(x: rect.minX + 5, y: rect.minY + 1.5), color: textColor, font: labelFont)
    }

    private func text(_ string: String, at point: NSPoint, color: NSColor, font: NSFont) {
        (string as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func hoveredIndex(range: Range<Int>) -> Int? {
        guard let point = crosshair, plotRect.contains(point) else { return nil }
        let index = range.lowerBound + Int((point.x - plotRect.minX) / slotWidth)
        return range.contains(index) ? index : nil
    }

    // MARK: Indicators

    private func recomputeIndicators() {
        let closes = candles.map(\.close)
        averages = Self.movingAveragePeriods.map { Self.simpleMovingAverage(closes, period: $0) }
        volumeAverage = Self.simpleMovingAverage(candles.map(\.volume), period: Self.volumeAveragePeriod)
    }

    static func simpleMovingAverage(_ values: [Double], period: Int) -> [Double?] {
        guard period > 0 else { return values.map { _ in nil } }
        var result = [Double?](repeating: nil, count: values.count)
        var sum = 0.0
        for index in values.indices {
            sum += values[index]
            if index >= period { sum -= values[index - period] }
            if index >= period - 1 { result[index] = sum / Double(period) }
        }
        return result
    }

    static func niceStep(for rawStep: Double) -> Double {
        guard rawStep > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(rawStep)))
        let normalized = rawStep / magnitude
        let nice: Double = normalized < 1.5 ? 1 : normalized < 3 ? 2 : normalized < 7 ? 5 : 10
        return nice * magnitude
    }

    private static var formatters: [String: DateFormatter] = [:]

    private static func formatter(_ format: String) -> DateFormatter {
        if let cached = formatters[format] { return cached }
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatters[format] = formatter
        return formatter
    }
}
