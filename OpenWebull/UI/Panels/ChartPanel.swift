import AppKit

/// Chart tab: drawing toolbar, the chart with its legend chip, and the range/interval footer.
final class ChartPanel: PanelViewController {
    var onShowNews: (() -> Void)?

    private let chart = CandleChartView()
    private let legendChip = ChartLegendChip()
    private var interval: ChartInterval = .fiveMinutes
    private var range: ChartRange = .oneDay
    private var drawingsBySymbol: [String: [ChartDrawing]] = [:]

    private var drawToggle: IconButton!
    private var trendLineButton: IconButton!
    private var horizontalLineButton: IconButton!
    private var magnetButton: IconButton!
    private var eyeButton: IconButton!
    private var drawingTools: NSStackView!
    private var rangeButton: TextTabButton!
    private var intervalButtons: [ChartInterval: TextTabButton] = [:]
    private var moreIntervalsButton: TextTabButton!

    private static let quickIntervals: [ChartInterval] = [.fiveMinutes, .fifteenMinutes, .thirtyMinutes]
    private static let otherIntervals: [ChartInterval] = [.oneMinute, .oneHour, .day, .week, .month]

    init(env: AppEnvironment) {
        super.init(env: env, title: "Chart")
    }

    override func buildContent() {
        let toolbar = makeToolbar()
        let footer = makeFooter()
        chart.onDrawingsChanged = { [unowned self] drawings in drawingsBySymbol[linkedSymbol] = drawings }
        chart.onToolFinished = { [unowned self] in updateToolButtons() }
        legendChip.onNews = { [unowned self] in onShowNews?() }
        legendChip.onAlert = { [unowned self] in promptForAlert() }

        view.addSubviews(toolbar, chart, legendChip, footer)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 31),
            chart.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            chart.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chart.bottomAnchor.constraint(equalTo: footer.topAnchor),
            legendChip.topAnchor.constraint(equalTo: chart.topAnchor, constant: 7),
            legendChip.leadingAnchor.constraint(equalTo: chart.leadingAnchor, constant: 8),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 31),
        ])
        applySelection()
    }

    override func refresh() {
        let symbol = linkedSymbol
        guard let instrument = env.market.instrument(symbol) else { return }
        let candles = env.market.candles(for: symbol, interval: interval)
        chart.symbol = symbol
        chart.interval = interval
        legendChip.update(symbol: symbol, name: instrument.name, interval: interval)

        var trailing = 0
        var countdown: String?
        if interval.isIntraday, let last = candles.last, let open = env.market.sessionOpen(for: symbol) {
            let sessionEnd = open.addingTimeInterval(Double(MarketSimulator.sessionMinutes) * 60)
            if range == .oneDay {
                trailing = max(0, Int(ceil(sessionEnd.timeIntervalSince(last.time) / interval.seconds)) - 1)
            }
            let remaining = max(0, Int(interval.seconds - Date().timeIntervalSince(last.time)))
            countdown = remaining >= 3600
                ? String(format: "%d:%02d:%02d", remaining / 3600, remaining / 60 % 60, remaining % 60)
                : String(format: "%02d:%02d", remaining / 60, remaining % 60)
        }
        chart.trailingEmptySlots = trailing
        chart.countdown = countdown
        chart.candles = candles
    }

    override func linkedSymbolDidChange(_ symbol: String) {
        chart.drawings = drawingsBySymbol[symbol] ?? []
        applyViewport()
        refresh()
    }

    // MARK: Toolbar

    private func makeToolbar() -> NSView {
        let indicators = IconButton(symbol: "chart.xyaxis.line", tooltip: "Indicators", target: self, action: #selector(showIndicatorMenu(_:)))
        drawToggle = IconButton(symbol: "pencil", tooltip: "Drawing Tools", target: self, action: #selector(toggleDrawingTools))
        drawToggle.isActive = true
        let style = IconButton(symbol: "chart.bar.fill", tooltip: "Chart Style", target: self, action: #selector(showStyleMenu(_:)))
        let reset = IconButton(symbol: "arrow.up.left.and.down.right.magnifyingglass", tooltip: "Reset Zoom", target: self, action: #selector(resetZoom))

        trendLineButton = IconButton(symbol: "line.diagonal", tooltip: "Trend Line", target: self, action: #selector(selectTrendLine))
        horizontalLineButton = IconButton(symbol: "minus", tooltip: "Horizontal Line", target: self, action: #selector(selectHorizontalLine))
        magnetButton = IconButton(symbol: "scope", tooltip: "Magnet: snap to open/high/low/close", target: self, action: #selector(toggleMagnet))
        magnetButton.showsActiveBackground = true
        magnetButton.activeTint = Theme.textPrimary
        magnetButton.isActive = true
        eyeButton = IconButton(symbol: "eye", tooltip: "Show / Hide Drawings", target: self, action: #selector(toggleDrawingsVisible))
        let trash = IconButton(symbol: "trash", tooltip: "Remove All Drawings", target: self, action: #selector(clearDrawings))

        drawingTools = NSStackView(views: [divider(), trendLineButton, horizontalLineButton, divider(), magnetButton, eyeButton, trash])
        drawingTools.spacing = 8
        let stack = NSStackView(views: [indicators, drawToggle, style, reset, drawingTools])
        stack.spacing = 8
        let bar = FillView(color: Theme.panelBackground)
        bar.borderEdges = [.bottom]
        bar.addSubviews(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    private func divider() -> NSView {
        let line = FillView(color: Theme.separator)
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        line.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return line
    }

    @objc private func showIndicatorMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let averages = NSMenuItem(title: "Moving Averages (5, 10, 20, 60)", action: #selector(toggleAverages), keyEquivalent: "")
        averages.state = chart.showsMovingAverages ? .on : .off
        let volume = NSMenuItem(title: "Volume", action: #selector(toggleVolume), keyEquivalent: "")
        volume.state = chart.showsVolume ? .on : .off
        for item in [averages, volume] {
            item.target = self
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func showStyleMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for (index, style) in CandleChartView.Style.allCases.enumerated() {
            let item = NSMenuItem(title: style.rawValue, action: #selector(selectStyle(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            item.state = chart.style == style ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func selectStyle(_ sender: NSMenuItem) { chart.style = CandleChartView.Style.allCases[sender.tag] }
    @objc private func toggleAverages() { chart.showsMovingAverages.toggle() }
    @objc private func toggleVolume() { chart.showsVolume.toggle() }
    @objc private func resetZoom() { applyViewport() }

    @objc private func toggleDrawingTools() {
        drawToggle.isActive.toggle()
        drawingTools.isHidden = !drawToggle.isActive
        if !drawToggle.isActive { chart.tool = .none }
        updateToolButtons()
    }

    @objc private func selectTrendLine() {
        chart.tool = chart.tool == .trendLine ? .none : .trendLine
        updateToolButtons()
    }

    @objc private func selectHorizontalLine() {
        chart.tool = chart.tool == .horizontalLine ? .none : .horizontalLine
        updateToolButtons()
    }

    @objc private func toggleMagnet() {
        chart.snapsToPrices.toggle()
        magnetButton.isActive = chart.snapsToPrices
    }

    @objc private func toggleDrawingsVisible() {
        chart.showsDrawings.toggle()
        eyeButton.image = NSImage(systemSymbolName: chart.showsDrawings ? "eye" : "eye.slash", accessibilityDescription: nil)
    }

    @objc private func clearDrawings() {
        chart.drawings = []
        drawingsBySymbol[linkedSymbol] = nil
    }

    private func updateToolButtons() {
        trendLineButton.isActive = chart.tool == .trendLine
        horizontalLineButton.isActive = chart.tool == .horizontalLine
    }

    // MARK: Footer

    private func makeFooter() -> NSView {
        rangeButton = TextTabButton(title: range.rawValue, target: self, action: #selector(showRangeMenu(_:)))
        rangeButton.showsDisclosure = true
        let intervalStack = NSStackView()
        intervalStack.spacing = 18
        for interval in Self.quickIntervals {
            let button = TextTabButton(title: interval.rawValue, target: self, action: #selector(selectQuickInterval(_:)))
            button.tag = ChartInterval.allCases.firstIndex(of: interval)!
            intervalButtons[interval] = button
            intervalStack.addArrangedSubview(button)
        }
        moreIntervalsButton = TextTabButton(title: "D", target: self, action: #selector(showIntervalMenu(_:)))
        moreIntervalsButton.showsDisclosure = true
        intervalStack.addArrangedSubview(moreIntervalsButton)

        let toggles = ToggleGroupView(items: [
            .init(title: "Night", isEnabled: false, tooltip: "Overnight session is not simulated"),
            .init(title: "Ext.", isEnabled: false, tooltip: "Extended hours are not simulated"),
            .init(title: "Auto", isEnabled: true, tooltip: "Auto-scale the price axis"),
        ], selected: [2])
        toggles.onToggle = { [unowned self] index, isOn in
            if index == 2 { chart.autoScale = isOn }
        }

        let rangeCaption = NSTextField.label("Range:", font: Theme.font(13), color: Theme.textSecondary)
        let intervalCaption = NSTextField.label("Interval:", font: Theme.font(13), color: Theme.textSecondary)
        let separator = FillView(color: Theme.separator)
        let bar = FillView(color: Theme.panelBackground)
        bar.borderEdges = [.top]
        bar.addSubviews(rangeCaption, rangeButton, separator, intervalCaption, intervalStack, toggles)
        NSLayoutConstraint.activate([
            rangeCaption.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            rangeCaption.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            rangeButton.leadingAnchor.constraint(equalTo: rangeCaption.trailingAnchor, constant: 14),
            rangeButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: rangeButton.trailingAnchor, constant: 14),
            separator.topAnchor.constraint(equalTo: bar.topAnchor),
            separator.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            intervalCaption.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 14),
            intervalCaption.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            intervalStack.leadingAnchor.constraint(equalTo: intervalCaption.trailingAnchor, constant: 18),
            intervalStack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            toggles.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            toggles.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    @objc private func showRangeMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for (index, candidate) in ChartRange.allCases.enumerated() {
            let item = NSMenuItem(title: candidate.rawValue, action: #selector(selectRange(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            item.state = candidate == range ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func showIntervalMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for candidate in Self.otherIntervals {
            let item = NSMenuItem(title: candidate.title, action: #selector(selectMenuInterval(_:)), keyEquivalent: "")
            item.tag = ChartInterval.allCases.firstIndex(of: candidate)!
            item.target = self
            item.state = candidate == interval ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func selectRange(_ sender: NSMenuItem) {
        range = ChartRange.allCases[sender.tag]
        if range.isIntraday != interval.isIntraday {
            interval = range.defaultInterval
        }
        applySelection()
    }

    @objc private func selectQuickInterval(_ sender: NSButton) {
        setInterval(ChartInterval.allCases[sender.tag])
    }

    @objc private func selectMenuInterval(_ sender: NSMenuItem) {
        setInterval(ChartInterval.allCases[sender.tag])
    }

    private func setInterval(_ newInterval: ChartInterval) {
        interval = newInterval
        if range.isIntraday != interval.isIntraday {
            range = ChartRange.defaultRange(for: interval)
        }
        applySelection()
    }

    private func applySelection() {
        rangeButton.label = range.rawValue
        for (candidate, button) in intervalButtons {
            button.isSelected = candidate == interval
        }
        let isOther = Self.otherIntervals.contains(interval)
        moreIntervalsButton.label = isOther ? interval.rawValue : "D"
        moreIntervalsButton.isSelected = isOther
        applyViewport()
        refresh()
    }

    /// 1D shows the whole session (bars so far plus the remaining empty slots); longer ranges
    /// show as much history as the range covers.
    private func applyViewport() {
        let available = env.market.candles(for: linkedSymbol, interval: interval).count
        chart.setVisibleBars(min(range.slots(for: interval), max(available, 10) + (range == .oneDay ? range.slots(for: interval) : 0)))
    }

    // MARK: Alerts

    private func promptForAlert() {
        guard let window = view.window, let quote = env.market.quote(for: linkedSymbol) else { return }
        let alert = NSAlert()
        alert.messageText = "Price Alert for \(linkedSymbol)"
        alert.informativeText = "Notify me when the last price crosses this level. Current: \(Format.legendPrice(quote.last))"
        let field = NSTextField.numberInput(placeholder: "Price", fractionDigits: 3)
        field.frame = NSRect(x: 0, y: 0, width: 180, height: 24)
        field.translatesAutoresizingMaskIntoConstraints = true
        field.doubleValue = quote.last
        alert.accessoryView = field
        alert.addButton(withTitle: "Create Alert")
        alert.addButton(withTitle: "Cancel")
        let symbol = linkedSymbol
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self, field.doubleValue > 0 else { return }
            self.env.alerts.add(symbol: symbol, price: field.doubleValue, currentPrice: quote.last)
        }
    }
}
