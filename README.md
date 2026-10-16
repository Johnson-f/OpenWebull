# OpenWebull

An open source desktop trading workstation for macOS, written in Swift with AppKit.
All market data, news and fills come from a built-in simulator — there is no real
data feed or brokerage connection.

## Features

- **Workspaces:** Watchlists, Stocks, Markets, Screener, Account, Day Trader, Swing Trader, Options — each a resizable split layout of tabbed panels.
- **Linked panels:** selecting a symbol anywhere retargets the chart, quote, Level 2, time & sales and order ticket.
- **Charting:** candles/line/area, 1m–monthly intervals, moving averages, volume, crosshair, scroll-to-zoom and drag-to-pan.
- **Paper trading:** market, limit, stop and stop-limit orders with Day/GTC/IOC, margin buying power, positions with realized and unrealized P&L.
- **Market data:** Level 2 depth, time & sales, options chain priced with Black–Scholes, sector heatmap, movers, screener.

## Building

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
open OpenWebull.xcodeproj
```

Or from the command line:

```bash
xcodebuild -project OpenWebull.xcodeproj -scheme OpenWebull -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/OpenWebull.app
xcodebuild -project OpenWebull.xcodeproj -scheme OpenWebull -derivedDataPath build/DerivedData test
```

## Layout

| Directory | Contents |
| --- | --- |
| `OpenWebull/Market` | Simulator: deterministic history, live random walk, order book, tape, news, option pricing |
| `OpenWebull/Trading` | `PaperBroker` order matching and account accounting |
| `OpenWebull/UI/Shell` | Window, navigation rail, top/status bars, workspace layout tree |
| `OpenWebull/UI/Panels` | Individual dockable panels |
| `OpenWebull/UI/Components` | Shared table, tab strip, sparkline and toast views |
| `OpenWebullTests` | Swift Testing suites for the broker, simulator and pricing |
