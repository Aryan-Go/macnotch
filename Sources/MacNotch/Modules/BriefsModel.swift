import AppKit
import Combine
import CoreLocation
import Foundation

/// Current conditions pulled from Apple's WeatherKit service using the token
/// the Weather app already stores on this Mac.
struct WeatherSnapshot: Equatable {
    var temperature: Double
    var conditionCode: String
    var high: Double
    var low: Double
    var location: String
    var isDaylight: Bool
    var isMetric: Bool

    var symbolName: String {
        WeatherSymbol.symbol(for: conditionCode, daylight: isDaylight)
    }

    var conditionLabel: String {
        WeatherSymbol.label(for: conditionCode)
    }

    func temperature(_ value: Double) -> String {
        let converted = isMetric ? value : value * 9 / 5 + 32
        return "\(Int(converted.rounded()))°"
    }
}

/// One row of the Stocks watchlist, read from the Stocks widget's cached quotes.
struct StockQuote: Identifiable, Equatable {
    var symbol: String
    var name: String
    var price: Double
    var change: Double
    var currencyCode: String

    var id: String { symbol }

    var changePercent: Double {
        let previous = price - change
        guard previous != 0 else { return 0 }
        return change / previous * 100
    }

    var isUp: Bool { change >= 0 }

    var priceString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = price >= 1000 ? 0 : 2
        return formatter.string(from: NSNumber(value: price)) ?? String(format: "%.2f", price)
    }

    var changeString: String {
        let sign = change >= 0 ? "+" : "−"
        return "\(sign)\(String(format: "%.2f", abs(change))) (\(sign)\(String(format: "%.2f", abs(changePercent)))%)"
    }
}

/// A recent Notification Center entry.
struct NotificationItem: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var body: String
    var appName: String
    var bundleID: String
    var date: Date
    var icon: NSImage?

    static func == (lhs: NotificationItem, rhs: NotificationItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// State of the notifications feed.
enum NotificationsState: Equatable {
    case loading
    case empty
    case permissionNeeded
    case items([NotificationItem])
}

/// Owns the three "brief" feeds shown in the Briefs tab. Each feed reads from
/// data the corresponding Apple app already keeps on this Mac.
@MainActor
final class BriefsModel: ObservableObject {
    @Published private(set) var weather: WeatherSnapshot?
    @Published private(set) var weatherNote: String?
    @Published private(set) var stocks: [StockQuote] = []
    @Published private(set) var stocksNote: String?
    @Published private(set) var notifications: NotificationsState = .loading

    private var timer: Timer?
    private var lastWeatherFetch = Date.distantPast
    private var weatherInFlight = false

    private let maxStocks = 4
    private let maxNotifications = 3

    // MARK: - Lifecycle

    func start() {
        refreshAll()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called when the panel opens so the tab is fresh the moment it appears.
    func refreshAll() {
        refreshWeather(force: true)
        refreshStocks()
        refreshNotifications()
    }

    private func tick() {
        if Date().timeIntervalSince(lastWeatherFetch) > 600 {
            refreshWeather(force: true)
        }
        refreshStocks()
        refreshNotifications()
    }

    // MARK: - Weather

    private func refreshWeather(force: Bool) {
        guard force || !weatherInFlight else { return }
        weatherInFlight = true
        Task { @MainActor in
            defer { weatherInFlight = false }
            let result = await WeatherProvider.fetch()
            self.lastWeatherFetch = Date()
            switch result {
            case .success(let snapshot):
                self.weather = snapshot
                self.weatherNote = nil
            case .failure(let note):
                self.weatherNote = note
            }
        }
    }

    // MARK: - Stocks

    private func refreshStocks() {
        Task.detached(priority: .utility) {
            let result = StocksProvider.fetch()
            await MainActor.run {
                switch result {
                case .success(let quotes):
                    self.stocks = Array(quotes.prefix(self.maxStocks))
                    self.stocksNote = quotes.isEmpty ? "No watchlist found" : nil
                case .failure(let error):
                    self.stocksNote = error.text
                }
            }
        }
    }

    // MARK: - Notifications

    private func refreshNotifications() {
        Task.detached(priority: .utility) {
            let result = NotificationsProvider.fetch()
            await MainActor.run {
                switch result {
                case .success(let items):
                    let trimmed = Array(items.prefix(self.maxNotifications))
                    self.notifications = trimmed.isEmpty ? .empty : .items(trimmed)
                case .failure(.permissionNeeded):
                    if case .items = self.notifications {} else {
                        self.notifications = .permissionNeeded
                    }
                case .failure(.unavailable):
                    self.notifications = .empty
                }
            }
        }
    }
}
