import CoreLocation
import Foundation

enum WeatherResult {
    case success(WeatherSnapshot)
    case failure(String)
}

/// Reads the current weather from Apple's WeatherKit service.
///
/// The Weather app (and its widget) already hold a short-lived WeatherKit token
/// on this Mac, plus a cache of the exact request URLs they use. We reuse both:
/// the freshest stored token authorises the call, and the cached request URL
/// carries the coordinates, timezone and client metadata the service expects.
enum WeatherProvider {
    private static let tokenPaths = [
        "Library/Containers/com.apple.weather.widget/Data/Library/Preferences/com.apple.weather.widget.plist",
        "Library/Containers/com.apple.weather/Data/Library/Preferences/com.apple.weather.plist"
    ]

    private static let cacheDB = "Library/Containers/com.apple.weather/Data/Library/Caches/com.apple.weather/Cache.db"

    static func fetch() async -> WeatherResult {
        guard let token = freshestToken() else {
            return .failure("Open the Weather app once to sign in")
        }
        guard let url = latestRequestURL() else {
            return .failure("Open the Weather app to cache a location")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return .failure(http.statusCode == 401
                    ? "Open the Weather app once to refresh"
                    : "Weather unavailable (\(http.statusCode))")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["currentWeather"] as? [String: Any]
            else { return .failure("Unexpected weather response") }

            let temperature = number(current["temperature"])
            let condition = current["conditionCode"] as? String ?? ""
            let daylight = current["daylight"] as? Bool ?? true
            let meta = current["metadata"] as? [String: Any] ?? [:]
            let latitude = number(meta["latitude"])
            let longitude = number(meta["longitude"])

            var high = temperature
            var low = temperature
            if let daily = json["forecastDaily"] as? [String: Any],
               let days = daily["days"] as? [[String: Any]],
               let today = days.first {
                high = number(today["temperatureMax"])
                low = number(today["temperatureMin"])
            }

            let place = await placeName(latitude: latitude, longitude: longitude)

            return .success(WeatherSnapshot(
                temperature: temperature,
                conditionCode: condition,
                high: high,
                low: low,
                location: place,
                isDaylight: daylight,
                isMetric: !usesFahrenheit
            ))
        } catch {
            return .failure("Weather unavailable")
        }
    }

    // MARK: - Local Apple app data

    /// The newest `wdsAuthToken` across the Weather app and widget preferences.
    private static func freshestToken() -> String? {
        let home = NSHomeDirectory()
        var best: String?
        for relative in tokenPaths {
            let path = home + "/" + relative
            guard let data = FileManager.default.contents(atPath: path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let token = plist["wdsAuthToken"] as? String,
                  !token.isEmpty
            else { continue }
            best = token
            break
        }
        return best
    }

    /// The most recently cached WeatherKit weather request, taken straight from
    /// the Weather app's URLCache so it already contains valid query parameters.
    private static func latestRequestURL() -> URL? {
        let path = NSHomeDirectory() + "/" + cacheDB
        let query = """
        SELECT request_key FROM cfurl_cache_response \
        WHERE request_key LIKE '%weatherkit.apple.com/api/v2/weather/%' \
        AND request_key LIKE '%currentWeather%' \
        ORDER BY time_stamp DESC LIMIT 1;
        """
        guard let output = runSQLite(path: path, query: query) else { return nil }
        let key = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        // The cache stores the key with a trailing "|<id>" fragment.
        let urlString = key.split(separator: "|").first.map(String.init) ?? key
        return URL(string: urlString)
    }

    private static func runSQLite(path: String, query: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [path, query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Helpers

    private static let geocoder = CLGeocoder()

    private static func placeName(latitude: Double, longitude: Double) async -> String {
        guard latitude != 0 || longitude != 0 else { return "" }
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let placemarks = try? await geocoder.reverseGeocodeLocation(location)
        if let mark = placemarks?.first {
            return mark.locality ?? mark.subAdministrativeArea ?? mark.administrativeArea ?? ""
        }
        return ""
    }

    private static var usesFahrenheit: Bool {
        if #available(macOS 13.0, *) {
            return Locale.current.measurementSystem == .us
        }
        return Locale.current.identifier.hasPrefix("en_US")
    }

    private static func number(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return 0
    }
}

/// Maps WeatherKit condition codes to SF Symbols and readable labels.
enum WeatherSymbol {
    static func symbol(for code: String, daylight: Bool) -> String {
        switch code {
        case "CLEAR", "MOSTLY_CLEAR", "HOT":
            return daylight ? "sun.max.fill" : "moon.stars.fill"
        case "PARTLY_CLOUDY":
            return daylight ? "cloud.sun.fill" : "cloud.moon.fill"
        case "CLOUDY", "OVERCAST":
            return "cloud.fill"
        case "FOG", "HAZE", "SMOKE":
            return "cloud.fog.fill"
        case "DRIZZLE", "FREEZING_DRIZZLE":
            return "cloud.drizzle.fill"
        case "RAIN", "FREEZING_RAIN", "MIXED_RAIN_SNOW":
            return "cloud.rain.fill"
        case "HEAVY_RAIN", "STRONG_STORMS":
            return "cloud.heavyrain.fill"
        case "SLEET":
            return "cloud.sleet.fill"
        case "SNOW", "FLURRIES", "BLOWING_SNOW":
            return "cloud.snow.fill"
        case "HEAVY_SNOW", "BLIZZARD", "FRIGID", "COLD":
            return "cloud.snow.fill"
        case "THUNDERSTORMS", "ISOLATED_THUNDERSTORMS", "SCATTERED_THUNDERSTORMS",
             "TROPICAL_STORM", "HURRICANE":
            return "cloud.bolt.rain.fill"
        case "WINDY", "BREEZY":
            return "wind"
        default:
            return "cloud.fill"
        }
    }

    static func label(for code: String) -> String {
        guard !code.isEmpty else { return "—" }
        return code
            .split(separator: "_")
            .map { $0.prefix(1) + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
