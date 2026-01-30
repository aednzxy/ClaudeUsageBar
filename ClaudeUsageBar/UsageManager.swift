import Foundation
import Security

enum UsageStatus {
    case unknown
    case green
    case orange
    case red
}

struct UsageWindow: Codable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct UsageResponse: Codable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let error: String?
    let fetchedAt: String?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case error
        case fetchedAt = "fetched_at"
    }
}

struct KeychainCredentials: Codable {
    let claudeAiOauth: OAuthToken?

    struct OAuthToken: Codable {
        let accessToken: String
    }
}

class UsageManager: ObservableObject {
    @Published var sessionUsage: Double?
    @Published var weeklyUsage: Double?
    @Published var sessionResetAt: Date?
    @Published var weeklyResetAt: Date?
    @Published var isLoading = false
    @Published var error: String?

    var onUpdate: (() -> Void)?
    private var timer: Timer?

    // Keychain service names to try
    private let keychainServices = [
        "Claude Code-credentials",
        "Claude Safe Storage"
    ]

    // Calculate status based on utilization directly (API returns percentage)
    var sessionStatus: UsageStatus {
        guard let usage = sessionUsage else { return .unknown }
        if usage >= 100 { return .red }

        // For 5-hour window: calculate time elapsed
        if let reset = sessionResetAt {
            let timeUntilReset = reset.timeIntervalSinceNow
            let periodDuration: TimeInterval = 5 * 60 * 60 // 5 hours in seconds
            let timeElapsed = periodDuration - timeUntilReset
            let timePercentage = max(0, min(100, (timeElapsed / periodDuration) * 100))

            if usage > timePercentage {
                return .orange
            }
        }
        return .green
    }

    var weeklyStatus: UsageStatus {
        guard let usage = weeklyUsage else { return .unknown }
        if usage >= 100 { return .red }

        // For 7-day window: calculate time elapsed
        if let reset = weeklyResetAt {
            let timeUntilReset = reset.timeIntervalSinceNow
            let periodDuration: TimeInterval = 7 * 24 * 60 * 60 // 7 days in seconds
            let timeElapsed = periodDuration - timeUntilReset
            let timePercentage = max(0, min(100, (timeElapsed / periodDuration) * 100))

            if usage > timePercentage {
                return .orange
            }
        }
        return .green
    }

    var sessionTimeRemaining: String {
        guard let reset = sessionResetAt else { return "--" }
        return formatTimeRemaining(until: reset)
    }

    var weeklyTimeRemaining: String {
        guard let reset = weeklyResetAt else { return "--" }
        return formatTimeRemaining(until: reset)
    }

    private func formatTimeRemaining(until date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "now" }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    func startPolling(interval: TimeInterval = 60) {
        fetchUsage()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetchUsage()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func fetchUsage() {
        isLoading = true
        error = nil

        // Get token from keychain (this will trigger prompt if needed)
        guard let token = getTokenFromKeychain() else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.error = "No credentials found. Please log in to Claude Code or Claude Desktop."
                self.onUpdate?()
            }
            return
        }

        // Fetch usage from API
        fetchUsageFromAPI(token: token)
    }

    private func getTokenFromKeychain() -> String? {
        for service in keychainServices {
            if let token = readKeychainItem(service: service) {
                return token
            }
        }
        return nil
    }

    private func readKeychainItem(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Parse the JSON to extract the OAuth token
        guard let jsonData = jsonString.data(using: .utf8),
              let credentials = try? JSONDecoder().decode(KeychainCredentials.self, from: jsonData),
              let token = credentials.claudeAiOauth?.accessToken else {
            return nil
        }

        return token
    }

    private func fetchUsageFromAPI(token: String) {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.error = "Invalid API URL"
                self.onUpdate?()
            }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.0.31", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.error = "Network error: \(error.localizedDescription)"
                    self?.onUpdate?()
                    return
                }

                guard let data = data else {
                    self?.error = "No data received"
                    self?.onUpdate?()
                    return
                }

                self?.parseUsageResponse(data: data)
            }
        }.resume()
    }

    private func parseUsageResponse(data: Data) {
        do {
            let response = try JSONDecoder().decode(UsageResponse.self, from: data)

            if let err = response.error {
                self.error = err
                onUpdate?()
                return
            }

            // Parse usage - API returns percentage directly (e.g., 16.0 means 16%)
            if let fiveHour = response.fiveHour {
                self.sessionUsage = fiveHour.utilization
                if let resetStr = fiveHour.resetsAt {
                    self.sessionResetAt = parseDate(resetStr)
                }
            }

            if let sevenDay = response.sevenDay {
                self.weeklyUsage = sevenDay.utilization
                if let resetStr = sevenDay.resetsAt {
                    self.weeklyResetAt = parseDate(resetStr)
                }
            }

            self.error = nil

        } catch {
            self.error = "Failed to parse response: \(error.localizedDescription)"
        }

        onUpdate?()
    }

    private func parseDate(_ string: String) -> Date? {
        let formatters = [
            ISO8601DateFormatter(),
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f
            }()
        ]

        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }

        // Try manual parsing for the specific format
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df.date(from: string)
    }
}
