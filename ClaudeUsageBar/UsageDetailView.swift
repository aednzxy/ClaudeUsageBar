import SwiftUI
import ServiceManagement

struct UsageDetailView: View {
    @ObservedObject var usageManager: UsageManager
    var onSettingsChange: (() -> Void)?

    @State private var showValues: Bool = UserDefaults.standard.bool(forKey: "showValues")
    @State private var showLabels: Bool = UserDefaults.standard.bool(forKey: "showLabels")
    @State private var launchAtLogin: Bool = {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Claude Usage")
                    .font(.headline)
                Spacer()
                Button(action: { usageManager.fetchUsage() }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(usageManager.isLoading)
            }

            Divider()

            if let error = usageManager.error {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Error")
                            .font(.subheadline.bold())
                    }
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                // Session Usage (5-hour)
                UsageRow(
                    title: "Session (5hr)",
                    usage: usageManager.sessionUsage,
                    status: usageManager.sessionStatus,
                    resetIn: usageManager.sessionTimeRemaining,
                    isLoading: usageManager.isLoading
                )

                // Weekly Usage (7-day)
                UsageRow(
                    title: "Weekly (7d)",
                    usage: usageManager.weeklyUsage,
                    status: usageManager.weeklyStatus,
                    resetIn: usageManager.weeklyTimeRemaining,
                    isLoading: usageManager.isLoading
                )
            }

            Divider()

            // Display settings
            HStack(spacing: 6) {
                ToggleButton(title: "Values", isOn: $showValues) {
                    UserDefaults.standard.set(showValues, forKey: "showValues")
                    if !showValues {
                        showLabels = false
                        UserDefaults.standard.set(false, forKey: "showLabels")
                    }
                    onSettingsChange?()
                }

                ToggleButton(title: "Labels", isOn: $showLabels, disabled: !showValues) {
                    UserDefaults.standard.set(showLabels, forKey: "showLabels")
                    onSettingsChange?()
                }

                Spacer()
            }

            // Open at login
            Toggle("Open at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: launchAtLogin) { newValue in
                    if #available(macOS 13.0, *) {
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Failed to update login item: \(error)")
                            launchAtLogin.toggle() // Revert on failure
                        }
                    }
                }

            Divider()

            // Footer
            HStack {
                Text("Updates every 60s")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
        }
        .padding()
        .frame(width: 280)
    }
}

struct UsageRow: View {
    let title: String
    let usage: Double?
    let status: UsageStatus
    let resetIn: String
    let isLoading: Bool

    var statusColor: Color {
        switch status {
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .unknown: return .gray
        }
    }

    var statusIcon: String {
        switch status {
        case .green: return "checkmark.circle.fill"
        case .orange: return "exclamationmark.triangle.fill"
        case .red: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let usage = usage {
                    Text("\(Int(usage))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(statusColor)
                } else {
                    Text("--")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    if let usage = usage {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(statusColor)
                            .frame(width: geometry.size.width * min(usage / 100, 1.0), height: 8)
                    }
                }
            }
            .frame(height: 8)

            HStack {
                Text("Resets in: \(resetIn)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if status == .orange {
                    Text("Slow down!")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if status == .red {
                    Text("Almost exhausted")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }
}

struct ToggleButton: View {
    let title: String
    @Binding var isOn: Bool
    var disabled: Bool = false
    var onChange: (() -> Void)?

    var body: some View {
        Button(action: {
            if !disabled {
                isOn.toggle()
                onChange?()
            }
        }) {
            Text(title)
                .font(.caption)
                .fontWeight(isOn ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn ? Color.accentColor : Color.gray.opacity(0.15))
                )
                .foregroundColor(isOn ? .white : (disabled ? .secondary : .primary))
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.5 : 1.0)
    }
}
