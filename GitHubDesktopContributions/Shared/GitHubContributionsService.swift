import Foundation

enum GitHubContributionsServiceError: LocalizedError {
    case invalidUsername
    case invalidResponse
    case httpStatus(Int)
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .invalidUsername:
            return "GitHub username is empty."
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case .httpStatus(let statusCode):
            return "GitHub request failed with status \(statusCode)."
        case .parseFailed:
            return "Could not parse GitHub contribution graph."
        }
    }
}

struct GitHubContributionsService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    func fetchHeatmap(for username: String) async throws -> GitHubContributionHeatmap {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else {
            print("[ContributionsService] Username is empty")
            throw GitHubContributionsServiceError.invalidUsername
        }

        let lowercased = trimmedUsername.lowercased()
        print("[ContributionsService] Fetching contributions for '\(lowercased)'")
        let html = try await fetchContributionsHTML(for: lowercased)
        print("[ContributionsService] Got HTML, length: \(html.count)")
        let days = try parseContributionDays(from: html)
        print("[ContributionsService] Parsed \(days.count) contribution days")
        return try buildHeatmap(for: trimmedUsername, from: days, fetchedAt: Date())
    }

    // MARK: - Networking

    /// Fetches contributions HTML using the profile XHR endpoint (small fragment),
    /// falling back to `/users/<name>/contributions`.
    private func fetchContributionsHTML(for username: String) async throws -> String {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username

        // Primary: XHR endpoint returns only the calendar fragment.
        let xhrURLString = "https://github.com/\(encoded)?action=show&controller=profiles&tab=contributions&user_id=\(encoded)"
        if let xhrURL = URL(string: xhrURLString) {
            do {
                let html = try await fetchPayload(from: xhrURL, xhr: true)
                if !html.isEmpty {
                    print("[ContributionsService] XHR endpoint succeeded")
                    return html
                }
            } catch {
                print("[ContributionsService] XHR endpoint failed: \(error.localizedDescription)")
            }
        }

        // Fallback: standard contributions page.
        print("[ContributionsService] Trying fallback endpoint")
        guard let fallbackURL = URL(string: "https://github.com/users/\(encoded)/contributions") else {
            throw GitHubContributionsServiceError.invalidResponse
        }
        return try await fetchPayload(from: fallbackURL, xhr: false)
    }

    private func fetchPayload(from url: URL, xhr: Bool) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("GitHubDesktopContributionsWidget/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        if xhr {
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubContributionsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubContributionsServiceError.httpStatus(httpResponse.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            throw GitHubContributionsServiceError.invalidResponse
        }

        return html
    }

    // MARK: - Parsing (Foundation-only, no external deps)

    private func parseContributionDays(from html: String) throws -> [GitHubContributionDay] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        // Step 1: Build a lookup from element ID → tooltip text.
        // <tool-tip ... for="contribution-day-component-0-0" ...>3 contributions on March 9th.</tool-tip>
        let tooltipPattern = #"<tool-tip[^>]*?\bfor\s*=\s*"([^"]*)"[^>]*>([^<]*)</tool-tip>"#
        let tooltipRegex = try NSRegularExpression(pattern: tooltipPattern, options: [.caseInsensitive])
        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)

        var tooltips: [String: String] = [:]
        tooltipRegex.enumerateMatches(in: html, options: [], range: fullRange) { match, _, _ in
            guard let match,
                  match.numberOfRanges >= 3,
                  let idRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html) else { return }
            tooltips[String(html[idRange])] = String(html[textRange])
        }

        // Step 2: Find all <td ...> tags that have both data-date and the ContributionCalendar-day class.
        // These tags are single-line in GitHub's output.
        let tdPattern = #"<td\b[^>]*\bdata-date\s*=\s*"([^"]*)"[^>]*>"#
        let tdRegex = try NSRegularExpression(pattern: tdPattern, options: [.caseInsensitive])

        let idAttrPattern = #"\bid\s*=\s*"([^"]*)""#
        let idRegex = try NSRegularExpression(pattern: idAttrPattern, options: [])

        let levelAttrPattern = #"\bdata-level\s*=\s*"([^"]*)""#
        let levelRegex = try NSRegularExpression(pattern: levelAttrPattern, options: [])

        var results: [GitHubContributionDay] = []
        results.reserveCapacity(400)

        tdRegex.enumerateMatches(in: html, options: [], range: fullRange) { match, _, _ in
            guard let match,
                  let dateRange = Range(match.range(at: 1), in: html),
                  let tagRange = Range(match.range, in: html) else { return }

            let dateString = String(html[dateRange])
            guard let date = dateFormatter.date(from: dateString) else { return }

            let tag = String(html[tagRange])
            let tagNSRange = NSRange(tag.startIndex..<tag.endIndex, in: tag)

            // Extract data-level.
            var level = -1
            if let levelMatch = levelRegex.firstMatch(in: tag, options: [], range: tagNSRange),
               let lvlRange = Range(levelMatch.range(at: 1), in: tag),
               let parsed = Int(tag[lvlRange]) {
                level = min(max(parsed, 0), 4)
            }

            // Extract id to look up tooltip.
            var count = 0
            if let idMatch = idRegex.firstMatch(in: tag, options: [], range: tagNSRange),
               let idRange = Range(idMatch.range(at: 1), in: tag) {
                let elementId = String(tag[idRange])
                if let tipText = tooltips[elementId] {
                    count = Self.extractContributionCount(from: tipText)
                }
            }

            // If no data-level, infer from count.
            if level < 0 {
                if count == 0 { level = 0 }
                else if count <= 2 { level = 1 }
                else if count <= 5 { level = 2 }
                else if count <= 9 { level = 3 }
                else { level = 4 }
            }

            results.append(GitHubContributionDay(date: date, count: count, level: level))
        }

        if results.isEmpty {
            throw GitHubContributionsServiceError.parseFailed
        }

        return results
    }

    /// Extracts the integer contribution count from tooltip text like
    /// "3 contributions on March 9th." or "No contributions on February 9th."
    private static func extractContributionCount(from text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("no ") {
            return 0
        }
        let parts = trimmed.components(separatedBy: " ")
        if let first = parts.first, let count = Int(first) {
            return max(0, count)
        }
        return 0
    }

    // MARK: - Mock data

    func mockHeatmap(for username: String) -> GitHubContributionHeatmap {
        let safeUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? WidgetSharedConfig.defaultUsername : username
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1

        let today = calendar.startOfDay(for: Date())
        let totalDays = 7 * 53

        var days: [GitHubContributionDay] = []
        days.reserveCapacity(totalDays)

        for index in 0..<totalDays {
            guard let date = calendar.date(byAdding: .day, value: -(totalDays - index - 1), to: today) else {
                continue
            }
            let seed = (index * 37 + 11) % 100
            let level: Int
            let count: Int

            switch seed {
            case 0..<55:
                level = 0
                count = 0
            case 55..<76:
                level = 1
                count = 1 + (seed % 2)
            case 76..<90:
                level = 2
                count = 3 + (seed % 3)
            case 90..<97:
                level = 3
                count = 6 + (seed % 4)
            default:
                level = 4
                count = 11 + (seed % 6)
            }

            days.append(GitHubContributionDay(date: date, count: count, level: level))
        }

        return (try? buildHeatmap(for: safeUsername, from: days, fetchedAt: Date())) ?? GitHubContributionHeatmap(
            username: safeUsername,
            weeks: [],
            totalContributions: 0,
            fetchedAt: Date()
        )
    }

    // MARK: - Grid builder

    private func buildHeatmap(for username: String, from days: [GitHubContributionDay], fetchedAt: Date) throws -> GitHubContributionHeatmap {
        let sortedDays = days.sorted(by: { $0.date < $1.date })
        guard let firstDay = sortedDays.first, let lastDay = sortedDays.last else {
            throw GitHubContributionsServiceError.parseFailed
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1

        let normalizedFirstDay = calendar.startOfDay(for: firstDay.date)
        let weekday = calendar.component(.weekday, from: normalizedFirstDay)
        let leadingPadding = (weekday - calendar.firstWeekday + 7) % 7

        guard let gridStartDay = calendar.date(byAdding: .day, value: -leadingPadding, to: normalizedFirstDay) else {
            throw GitHubContributionsServiceError.parseFailed
        }

        let normalizedLastDay = calendar.startOfDay(for: lastDay.date)
        guard let daySpan = calendar.dateComponents([.day], from: gridStartDay, to: normalizedLastDay).day else {
            throw GitHubContributionsServiceError.parseFailed
        }

        let weekCount = (daySpan / 7) + 1
        var weeks = Array(repeating: Array(repeating: GitHubContributionCell.empty, count: 7), count: weekCount)
        var total = 0

        for day in sortedDays {
            let normalizedDate = calendar.startOfDay(for: day.date)
            guard let offset = calendar.dateComponents([.day], from: gridStartDay, to: normalizedDate).day else {
                continue
            }

            guard offset >= 0 else { continue }

            let weekIndex = offset / 7
            let dayIndex = offset % 7

            guard weekIndex < weeks.count, dayIndex < 7 else {
                continue
            }

            let level = min(max(day.level, 0), 4)
            weeks[weekIndex][dayIndex] = GitHubContributionCell(date: normalizedDate, count: day.count, level: level)
            total += day.count
        }

        return GitHubContributionHeatmap(
            username: username,
            weeks: weeks,
            totalContributions: total,
            fetchedAt: fetchedAt
        )
    }
}
