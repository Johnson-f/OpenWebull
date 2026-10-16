import AppKit

/// The trade ticket for the linked symbol, routed to the paper broker.
final class OrderEntryPanel: PanelViewController {
    private var side: OrderSide = .buy
    private let symbolLabel = NSTextField.label(font: Theme.font(15, .bold))
    private let nameLabel = NSTextField.label(font: Theme.font(11), color: Theme.textSecondary)
    private var bidButton: NSButton!
    private var askButton: NSButton!
    private var buyButton: FilledButton!
    private var sellButton: FilledButton!
    private var typePicker: NSPopUpButton!
    private var timeInForcePicker: NSPopUpButton!
    private let quantityField = NSTextField.numberInput(placeholder: "Qty", fractionDigits: 0)
    private let limitField = NSTextField.numberInput(placeholder: "Limit", fractionDigits: 2)
    private let stopField = NSTextField.numberInput(placeholder: "Stop", fractionDigits: 2)
    private var limitRow: NSGridRow!
    private var stopRow: NSGridRow!
    private let estimateLabel = NSTextField.label("--", font: Theme.numberFont(12), alignment: .right)
    private let buyingPowerLabel = NSTextField.label("--", font: Theme.numberFont(12), alignment: .right)
    private let positionLabel = NSTextField.label("--", font: Theme.numberFont(12), alignment: .right)
    private var submitButton: FilledButton!
    private let messageLabel = NSTextField.label(font: Theme.font(11.5))

    init(env: AppEnvironment) {
        super.init(env: env, title: "Trade")
    }

    override func buildContent() {
        bidButton = quoteButton(action: #selector(useBid))
        askButton = quoteButton(action: #selector(useAsk))
        buyButton = FilledButton(title: "Buy", color: Theme.up, target: self, action: #selector(selectBuy))
        sellButton = FilledButton(title: "Sell", color: Theme.down, target: self, action: #selector(selectSell))
        typePicker = .make(items: OrderType.allCases.map(\.rawValue), target: self, action: #selector(typeChanged))
        typePicker.selectItem(withTitle: OrderType.limit.rawValue)
        timeInForcePicker = .make(items: TimeInForce.allCases.map(\.rawValue), target: self, action: #selector(inputsChanged))
        submitButton = FilledButton(title: "Buy", color: Theme.up, target: self, action: #selector(submit))
        quantityField.integerValue = 10
        [quantityField, limitField, stopField].forEach { field in
            field.target = self
            field.action = #selector(inputsChanged)
            field.delegate = self
        }
        messageLabel.maximumNumberOfLines = 3
        messageLabel.lineBreakMode = .byWordWrapping

        let identity = NSStackView(views: [symbolLabel, nameLabel])
        identity.alignment = .firstBaseline
        identity.spacing = 8
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let quotes = NSStackView(views: [bidButton, askButton])
        quotes.distribution = .fillEqually
        let sides = NSStackView(views: [buyButton, sellButton])
        sides.distribution = .fillEqually
        sides.spacing = 6

        let grid = NSGridView(views: [
            [caption("Order Type"), typePicker],
            [caption("Quantity"), stepped(quantityField, increment: 1, action: #selector(stepQuantity(_:)))],
            [caption("Limit Price"), stepped(limitField, increment: 0.01, action: #selector(stepLimit(_:)))],
            [caption("Stop Price"), stepped(stopField, increment: 0.01, action: #selector(stepStop(_:)))],
            [caption("Time in Force"), timeInForcePicker],
            [caption("Est. Amount"), estimateLabel],
            [caption("Buying Power"), buyingPowerLabel],
            [caption("Position"), positionLabel],
        ])
        grid.rowSpacing = 7
        grid.columnSpacing = 10
        grid.column(at: 1).xPlacement = .fill
        grid.rowAlignment = .lastBaseline
        limitRow = grid.row(at: 2)
        stopRow = grid.row(at: 3)

        let stack = NSStackView(views: [identity, quotes, sides, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10

        // The ticket scrolls rather than letting Auto Layout squash its labels in short panes.
        let document = FlippedView()
        document.addSubviews(stack)
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = document
        let footer = FillView(color: Theme.panelBackground)
        footer.borderEdges = [.top]
        footer.addSubviews(submitButton, messageLabel)
        view.addSubviews(scrollView, footer)
        document.translatesAutoresizingMaskIntoConstraints = false
        let clip = scrollView.contentView
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            submitButton.topAnchor.constraint(equalTo: footer.topAnchor, constant: 10),
            submitButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 12),
            submitButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            messageLabel.topAnchor.constraint(equalTo: submitButton.bottomAnchor, constant: 6),
            messageLabel.leadingAnchor.constraint(equalTo: submitButton.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: submitButton.trailingAnchor),
            messageLabel.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -8),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.widthAnchor.constraint(equalTo: clip.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12),
            quotes.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sides.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sides.heightAnchor.constraint(equalToConstant: 26),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            submitButton.heightAnchor.constraint(equalToConstant: 32),
        ])

        env.orderTicketPrice.observe(self) { [weak self] price in
            guard let self, self.isViewLoaded else { return }
            if self.currentType == .market || self.currentType == .stop {
                self.typePicker.selectItem(withTitle: OrderType.limit.rawValue)
            }
            self.limitField.doubleValue = price
            self.typeChanged()
        }
        env.broker.changed.observe(self) { [weak self] in self?.updateAccountRows() }
        selectBuy()
        typeChanged()
    }

    override func refresh() {
        guard let instrument = env.market.instrument(linkedSymbol), let quote = env.market.quote(for: linkedSymbol) else { return }
        symbolLabel.stringValue = instrument.symbol
        nameLabel.stringValue = instrument.name
        setQuoteButton(bidButton, title: "Bid", price: quote.bid, size: quote.bidSize, color: Theme.up)
        setQuoteButton(askButton, title: "Ask", price: quote.ask, size: quote.askSize, color: Theme.down)
        submitButton.isEnabled = instrument.isTradable
        updateAccountRows()
    }

    override func linkedSymbolDidChange(_ symbol: String) {
        messageLabel.stringValue = ""
        if let quote = env.market.quote(for: symbol) {
            limitField.doubleValue = side == .buy ? quote.bid : quote.ask
            stopField.stringValue = ""
        }
        refresh()
        updateSubmitTitle()
    }

    // MARK: Actions

    @objc private func selectBuy() {
        side = .buy
        sideChanged()
    }

    @objc private func selectSell() {
        side = .sell
        sideChanged()
    }

    @objc private func typeChanged() {
        limitRow.isHidden = !currentType.needsLimitPrice
        stopRow.isHidden = !currentType.needsStopPrice
        if currentType.needsLimitPrice, limitField.doubleValue == 0, let quote = env.market.quote(for: linkedSymbol) {
            limitField.doubleValue = side == .buy ? quote.bid : quote.ask
        }
        inputsChanged()
    }

    @objc private func inputsChanged() {
        updateAccountRows()
        updateSubmitTitle()
    }

    @objc private func useBid() {
        if let quote = env.market.quote(for: linkedSymbol) { env.orderTicketPrice.send(quote.bid) }
    }

    @objc private func useAsk() {
        if let quote = env.market.quote(for: linkedSymbol) { env.orderTicketPrice.send(quote.ask) }
    }

    @objc private func stepQuantity(_ sender: NSStepper) { step(quantityField, sender, minimum: 1) }
    @objc private func stepLimit(_ sender: NSStepper) { step(limitField, sender, minimum: 0.01) }
    @objc private func stepStop(_ sender: NSStepper) { step(stopField, sender, minimum: 0.01) }

    @objc private func submit() {
        view.window?.makeFirstResponder(nil)
        let ticket = OrderTicket(
            symbol: linkedSymbol,
            side: side,
            type: currentType,
            quantity: quantityField.integerValue,
            limitPrice: currentType.needsLimitPrice ? limitField.doubleValue : nil,
            stopPrice: currentType.needsStopPrice ? stopField.doubleValue : nil,
            timeInForce: TimeInForce.allCases[timeInForcePicker.indexOfSelectedItem]
        )
        switch env.broker.place(ticket) {
        case let .success(order):
            let state = order.status == .filled ? "filled at \(Format.price(order.averageFillPrice ?? 0))" : order.status.rawValue.lowercased()
            show("\(side.rawValue) \(ticket.quantity) \(ticket.symbol) \(state).", color: Theme.trendColor(side.sign))
        case let .failure(rejection):
            show(rejection.message, color: Theme.warning)
        }
    }

    // MARK: Helpers

    private var currentType: OrderType {
        OrderType.allCases[max(typePicker.indexOfSelectedItem, 0)]
    }

    private func sideChanged() {
        buyButton.isActive = side == .buy
        sellButton.isActive = side == .sell
        submitButton.fillColor = side == .buy ? Theme.up : Theme.down
        inputsChanged()
    }

    private func updateSubmitTitle() {
        let price = currentType.needsLimitPrice ? " @ \(Format.price(limitField.doubleValue))" : ""
        submitButton.title = "\(side.rawValue) \(max(quantityField.integerValue, 0)) \(linkedSymbol)\(price)"
    }

    private func updateAccountRows() {
        guard isViewLoaded, let quote = env.market.quote(for: linkedSymbol) else { return }
        let price = currentType.needsLimitPrice ? limitField.doubleValue : (side == .buy ? quote.ask : quote.bid)
        estimateLabel.stringValue = Format.currency(price * Double(max(quantityField.integerValue, 0)))
        buyingPowerLabel.stringValue = Format.currency(env.broker.snapshot().buyingPower)
        if let position = env.broker.position(for: linkedSymbol) {
            positionLabel.stringValue = "\(position.quantity) @ \(Format.price(position.averageCost))"
            positionLabel.textColor = Theme.trendColor(position.unrealizedPnL(at: quote.last))
        } else {
            positionLabel.stringValue = "None"
            positionLabel.textColor = Theme.textSecondary
        }
    }

    private func show(_ message: String, color: NSColor) {
        messageLabel.stringValue = message
        messageLabel.textColor = color
    }

    private func step(_ field: NSTextField, _ stepper: NSStepper, minimum: Double) {
        field.doubleValue = max(minimum, field.doubleValue + stepper.doubleValue)
        stepper.doubleValue = 0
        inputsChanged()
    }

    private func caption(_ text: String) -> NSTextField {
        .label(text, font: Theme.font(11.5), color: Theme.textSecondary)
    }

    private func stepped(_ field: NSTextField, increment: Double, action: Selector) -> NSView {
        let stepper = NSStepper()
        stepper.minValue = -1_000_000
        stepper.maxValue = 1_000_000
        stepper.increment = increment
        stepper.valueWraps = false
        stepper.controlSize = .small
        stepper.target = self
        stepper.action = action
        let stack = NSStackView(views: [field, stepper])
        stack.spacing = 4
        return stack
    }

    private func quoteButton(action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.isBordered = false
        button.alignment = .left
        button.toolTip = "Use this price for the limit"
        return button
    }

    private func setQuoteButton(_ button: NSButton, title: String, price: Double, size: Int, color: NSColor) {
        let text = NSMutableAttributedString(string: "\(title) ", attributes: [.font: Theme.font(11), .foregroundColor: Theme.textSecondary])
        text.append(NSAttributedString(string: Format.price(price), attributes: [.font: Theme.numberFont(13, .semibold), .foregroundColor: color]))
        text.append(NSAttributedString(string: " × \(size / 100)", attributes: [.font: Theme.numberFont(11), .foregroundColor: Theme.textSecondary]))
        button.attributedTitle = text
    }
}

extension OrderEntryPanel: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        inputsChanged()
    }
}
