import Foundation

enum StocksError: Error {
    case message(String)

    var text: String {
        switch self {
        case .message(let text): return text
        }
    }
}

/// Reads the user's watchlist quotes that the Stocks app/widget has already
/// cached on this Mac. No network and no permissions required.
enum StocksProvider {
    private static let quotesDir =
        "Library/Containers/com.apple.stocks.widget/Data/Library/Caches/com.apple.stocks.widget/fsCachedData"

    static func fetch() -> Result<[StockQuote], StocksError> {
        let directory = NSHomeDirectory() + "/" + quotesDir
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory) else {
            return .failure(.message("Open the Stocks app once to cache quotes"))
        }

        let files = names
            .map { directory + "/" + $0 }
            .compactMap { path -> (String, Date)? in
                let attributes = try? manager.attributesOfItem(atPath: path)
                let date = attributes?[.modificationDate] as? Date ?? .distantPast
                return (path, date)
            }
            .sorted { $0.1 > $1.1 }

        let marker = Data("\"quotes\"".utf8)
        for (path, _) in files {
            guard let data = manager.contents(atPath: path),
                  data.range(of: marker) != nil,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawQuotes = object["quotes"] as? [[String: Any]]
            else { continue }

            let quotes = rawQuotes.compactMap(quote(from:))
            if !quotes.isEmpty { return .success(quotes) }
        }

        return .success([])
    }

    private static func quote(from raw: [String: Any]) -> StockQuote? {
        guard let symbol = raw["symbol"] as? String, !symbol.isEmpty else { return nil }
        guard let detail = raw["quoteDetail"] as? [String: Any] else { return nil }

        let price = number(detail["price"])
        guard price > 0 else { return nil }

        return StockQuote(
            symbol: symbol,
            name: raw["name"] as? String ?? symbol,
            price: price,
            change: number(detail["priceChange"]),
            currencyCode: detail["currencyCode"] as? String ?? "USD"
        )
    }

    private static func number(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return 0
    }
}
