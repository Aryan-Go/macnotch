import AppKit
import SwiftUI

/// The "Briefs" tab: a compact at-a-glance feed of weather, stocks and recent
/// notifications, all sourced from the apps Apple already has on this Mac.
struct BriefsView: View {
    @ObservedObject var model: BriefsModel

    var body: some View {
        VStack(spacing: 12) {
            weatherCard
            stocksSection
            notificationsSection
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .onAppear { model.refreshAll() }
    }

    // MARK: - Weather

    private var weatherCard: some View {
        HStack(spacing: 14) {
            Image(systemName: model.weather?.symbolName ?? "cloud.sun.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 38)

            VStack(alignment: .leading, spacing: 1) {
                if let weather = model.weather {
                    Text(weather.temperature(weather.temperature))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(weather.conditionLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    Text("—")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Weather")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer()

            if let weather = model.weather {
                VStack(alignment: .trailing, spacing: 2) {
                    if !weather.location.isEmpty {
                        Text(weather.location)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    Text("H \(weather.temperature(weather.high))  L \(weather.temperature(weather.low))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            } else if let note = model.weatherNote {
                Text(note)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 190, alignment: .trailing)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    // MARK: - Stocks

    private var stocksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Stocks", systemName: "chart.line.uptrend.xyaxis")

            if model.stocks.isEmpty {
                placeholder(model.stocksNote ?? "No watchlist found")
            } else {
                VStack(spacing: 5) {
                    ForEach(model.stocks) { quote in
                        stockRow(quote)
                    }
                }
            }
        }
    }

    private func stockRow(_ quote: StockQuote) -> some View {
        HStack(spacing: 10) {
            Text(quote.symbol)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 58, alignment: .leading)

            Text(quote.name)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(quote.priceString)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .monospacedDigit()

            Text(quote.changeString)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(quote.isUp ? .green : .red)
                .monospacedDigit()
                .frame(width: 118, alignment: .trailing)
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Notifications", systemName: "bell.badge.fill")
            ScrollView(.vertical, showsIndicators: true) {
                notificationsBody
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var notificationsBody: some View {
        switch model.notifications {
        case .loading:
            placeholder("Loading…")

        case .empty:
            placeholder("No recent notifications")

        case .permissionNeeded:
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Grant Full Disk Access to see notifications")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Already enabled? Remove and re-add MacNotch, then reopen")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.38))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .padding(.vertical, 2)

        case .items(let items):
            VStack(spacing: 6) {
                ForEach(items) { item in
                    notificationRow(item)
                }
            }
        }
    }

    private func notificationRow(_ item: NotificationItem) -> some View {
        let lines = item.displayLines
        return HStack(spacing: 10) {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.appName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(item.date.formatted(.relative(presentation: .numeric)))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                if !lines.headline.isEmpty {
                    Text(lines.headline)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                if !lines.detail.isEmpty {
                    Text(lines.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Shared bits

    private func sectionHeader(_ title: String, systemName: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
        }
        .foregroundStyle(.white.opacity(0.4))
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }
}
