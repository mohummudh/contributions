import Foundation

struct GitHubContributionDay: Hashable {
    let date: Date
    let count: Int
    let level: Int
}

struct GitHubContributionCell: Hashable {
    let date: Date?
    let count: Int
    let level: Int

    static let empty = GitHubContributionCell(date: nil, count: 0, level: 0)
}

struct GitHubContributionHeatmap: Hashable {
    let username: String
    let weeks: [[GitHubContributionCell]]
    let totalContributions: Int
    let todayContributions: Int
    let fetchedAt: Date

    var totalOverTodayText: String {
        "\(totalContributions) / \(todayContributions)"
    }
}
