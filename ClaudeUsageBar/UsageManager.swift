import Foundation

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

class UsageManager: ObservableObject {
    @Published var sessionUsage: Double?
    @Published var weeklyUsage: Double?
    @Published var sessionResetAt: Date?
    @Published var weeklyResetAt: Date?
    @Published var isLoading = false
    @Published var error: String?

    var onUpdate: (() -> Void)?
    private var timer: Timer?

    private let cacheFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude")
        .appendingPathComponent("usage-cache.json")

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

        // Run the fetch script in background
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.runFetchScript()

            // Then read the cache file
            DispatchQueue.main.async {
                self?.readCacheFile()
            }
        }
    }

    private func runFetchScript() {
        // Try running the bundled script first, fall back to installed location
        let scriptLocations = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/fetch-usage.sh"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude")
                .appendingPathComponent("fetch-usage.sh"),
            URL(fileURLWithPath: "/Applications/ClaudeUsageBar.app/Contents/Resources/fetch-usage.sh")
        ]

        var scriptPath: String?
        for location in scriptLocations {
            if FileManager.default.fileExists(atPath: location.path) {
                scriptPath = location.path
                break
            }
        }

        // If not found, create it in ~/.claude/
        if scriptPath == nil {
            print("fetch-usage.sh not found in any expected location, creating...")
            let destPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude")
                .appendingPathComponent("fetch-usage.sh")

            // Script content inline as fallback
            let scriptContent = """
            #!/bin/bash
            CACHE_FILE="$HOME/.claude/usage-cache.json"
            get_token() {
                local creds token
                # Try Claude Code CLI credentials first
                creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
                if [ -n "$creds" ]; then
                    token=$(echo "$creds" | python3 -c "import sys,json; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" 2>/dev/null)
                    if [ -n "$token" ]; then echo "$token"; return 0; fi
                fi
                # Fall back to Claude Desktop app credentials
                creds=$(security find-generic-password -s "Claude Safe Storage" -w 2>/dev/null)
                if [ -n "$creds" ]; then
                    token=$(echo "$creds" | python3 -c "import sys,json; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" 2>/dev/null)
                    if [ -n "$token" ]; then echo "$token"; return 0; fi
                fi
                return 1
            }
            TOKEN=$(get_token)
            if [ -z "$TOKEN" ]; then
                echo '{"error": "Could not get token"}' > "$CACHE_FILE"
                exit 1
            fi
            USAGE=$(curl -s -H "Authorization: Bearer $TOKEN" -H "anthropic-beta: oauth-2025-04-20" -H "User-Agent: claude-code/2.0.31" "https://api.anthropic.com/api/oauth/usage")
            TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            echo "$USAGE" | python3 -c "import sys,json; d=json.load(sys.stdin); d['fetched_at']='$TIMESTAMP'; print(json.dumps(d))" > "$CACHE_FILE"
            """

            try? scriptContent.write(to: destPath, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath.path)
            scriptPath = destPath.path
        }

        guard let finalPath = scriptPath else {
            print("Could not create or find fetch script")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [finalPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("Failed to run fetch script: \(error)")
        }
    }

    private func readCacheFile() {
        isLoading = false

        guard FileManager.default.fileExists(atPath: cacheFile.path) else {
            error = "No cache file. Run fetch-usage.sh first."
            onUpdate?()
            return
        }

        do {
            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            let response = try decoder.decode(UsageResponse.self, from: data)

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
            self.error = "Failed to parse cache: \(error.localizedDescription)"
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
