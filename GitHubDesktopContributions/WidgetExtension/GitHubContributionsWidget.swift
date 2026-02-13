import SwiftUI
import WidgetKit
import AppIntents

private let service = GitHubContributionsService()

// MARK: - App Intent (configurable username)

struct GitHubUsernameIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "GitHub Username"
    static var description: IntentDescription = "Set the GitHub username to show contributions for."

    @Parameter(title: "Username", default: "octocat")
    var username: String
}

// MARK: - Timeline

struct GitHubContributionsEntry: TimelineEntry {
    let date: Date
    let username: String
    let heatmap: GitHubContributionHeatmap?
    let errorMessage: String?
}

struct GitHubContributionsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GitHubContributionsEntry {
        let username = WidgetSharedConfig.defaultUsername
        return GitHubContributionsEntry(
            date: Date(),
            username: username,
            heatmap: service.mockHeatmap(for: username),
            errorMessage: nil
        )
    }

    func snapshot(for configuration: GitHubUsernameIntent, in context: Context) async -> GitHubContributionsEntry {
        let username = configuration.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveUsername = username.isEmpty ? WidgetSharedConfig.defaultUsername : username
        return GitHubContributionsEntry(
            date: Date(),
            username: effectiveUsername,
            heatmap: service.mockHeatmap(for: effectiveUsername),
            errorMessage: nil
        )
    }

    func timeline(for configuration: GitHubUsernameIntent, in context: Context) async -> Timeline<GitHubContributionsEntry> {
        let username = configuration.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveUsername = username.isEmpty ? WidgetSharedConfig.defaultUsername : username
        print("[Widget] timeline called, username: '\(effectiveUsername)'")

        do {
            let heatmap = try await service.fetchHeatmap(for: effectiveUsername)
            print("[Widget] Successfully fetched heatmap with \(heatmap.totalContributions) contributions")
            let entry = GitHubContributionsEntry(
                date: Date(),
                username: effectiveUsername,
                heatmap: heatmap,
                errorMessage: nil
            )
            let refreshDate = Date().addingTimeInterval(30 * 60)
            return Timeline(entries: [entry], policy: .after(refreshDate))
        } catch {
            print("[Widget] Error: \(error.localizedDescription)")
            let entry = GitHubContributionsEntry(
                date: Date(),
                username: effectiveUsername,
                heatmap: nil,
                errorMessage: error.localizedDescription
            )
            let retryDate = Date().addingTimeInterval(10 * 60)
            return Timeline(entries: [entry], policy: .after(retryDate))
        }
    }
}

struct GitHubContributionsWidget: Widget {
    let kind = "GitHubContributionsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: GitHubUsernameIntent.self, provider: GitHubContributionsProvider()) { entry in
            GitHubContributionsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("GitHub Contributions")
        .description("Shows your GitHub contribution heatmap. Right-click → Edit to set your username.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct GitHubContributionsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GitHubContributionsEntry

    private var maxWeeks: Int {
        switch family {
        case .systemSmall:
            return 22
        case .systemMedium:
            return 36
        case .systemLarge:
            return 53
        default:
            return 28
        }
    }

    private var cellSize: CGFloat {
        switch family {
        case .systemSmall:
            return 5
        case .systemMedium:
            return 6
        case .systemLarge:
            return 8
        default:
            return 6
        }
    }

    private var cellSpacing: CGFloat { 2 }

    // GitHub dark theme background
    private let bgColor = Color(red: 13/255, green: 17/255, blue: 23/255)

    var body: some View {
        if let heatmap = entry.heatmap {
            content(for: heatmap)
                .containerBackground(for: .widget) {
                    bgColor
                }
        } else {
            errorContent
                .containerBackground(for: .widget) {
                    bgColor
                }
        }
    }

    @ViewBuilder
    private func content(for heatmap: GitHubContributionHeatmap) -> some View {
        let visibleWeeks = Array(heatmap.weeks.suffix(maxWeeks))

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("@\(heatmap.username)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                if family != .systemSmall {
                    Text("\(heatmap.totalContributions)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            HStack(alignment: .top, spacing: cellSpacing) {
                ForEach(visibleWeeks.indices, id: \.self) { weekIndex in
                    VStack(spacing: cellSpacing) {
                        ForEach(0..<7, id: \.self) { dayIndex in
                            let cell = visibleWeeks[weekIndex][dayIndex]
                            contributionCell(level: cell.level)
                        }
                    }
                }
            }

            if family != .systemSmall {
                Text("Updated \(entry.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }
        }
        .padding(12)
    }

    private var errorContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("@\(entry.username)")
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(entry.errorMessage ?? "Unable to load contributions right now.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(3)
            Text("Retrying automatically")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(12)
    }

    @ViewBuilder
    private func contributionCell(level: Int) -> some View {
        let clamped = min(max(level, 0), 4)
        
    }

    private func cellOpacity(for level: Int) -> Double {
        switch level {
        case 0: return 0.03
        case 1: return 0.12
        case 2: return 0.25
        case 3: return 0.40
        default: return 0.55
        }
    }
}

