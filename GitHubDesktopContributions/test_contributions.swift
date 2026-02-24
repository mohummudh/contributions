import Foundation

// --- Mocking WidgetSharedConfig ---
enum WidgetSharedConfig {
    static let defaultUsername = "octocat"
}

// --- GitHubContributionModels.swift ---
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

// --- GitHubContributionsService.swift (Adapted) ---

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
        // print("[ContributionsService] Got HTML, length: \(html.count)")
        let days = try parseContributionDays(from: html)
        let totalFromSummary = Self.extractAnnualTotal(from: html)
        print("[ContributionsService] Parsed \(days.count) contribution days")
        return try buildHeatmap(
            for: trimmedUsername,
            from: days,
            fetchedAt: Date(),
            totalOverride: totalFromSummary
        )
    }

    // MARK: - Networking

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

        // Step 1: Build a lookup from element ID -> tooltip text.
        let tooltipPattern = #"<tool-tip[^>]*?\bfor\s*=\s*"([^"]*)"[^>]*>(.*?)</tool-tip>"#
        let tooltipRegex = try NSRegularExpression(
            pattern: tooltipPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)

        var tooltips: [String: String] = [:]
        tooltipRegex.enumerateMatches(in: html, options: [], range: fullRange) { match, _, _ in
            guard let match,
                  match.numberOfRanges >= 3,
                  let idRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html) else { return }
            let tooltipText = Self.plainText(fromHTML: String(html[textRange]))
            tooltips[String(html[idRange])] = tooltipText
        }

        // Step 2: Parse day cells from either table (<td>) or SVG (<rect>) payloads.
        let dayPattern = #"<(?:td|rect)\b[^>]*\bdata-date\s*=\s*"([^"]*)"[^>]*>"#
        let dayRegex = try NSRegularExpression(pattern: dayPattern, options: [.caseInsensitive])

        let idAttrPattern = #"\bid\s*=\s*"([^"]*)""#
        let idRegex = try NSRegularExpression(pattern: idAttrPattern, options: [])

        let levelAttrPattern = #"\bdata-level\s*=\s*"([^"]*)""#
        let levelRegex = try NSRegularExpression(pattern: levelAttrPattern, options: [])

        let countAttrPattern = #"\bdata-count\s*=\s*"([^"]*)""#
        let countRegex = try NSRegularExpression(pattern: countAttrPattern, options: [])

        let ariaLabelPattern = #"\baria-label\s*=\s*"([^"]*)""#
        let ariaLabelRegex = try NSRegularExpression(pattern: ariaLabelPattern, options: [])

        var daysByDate: [Date: GitHubContributionDay] = [:]
        daysByDate.reserveCapacity(400)

        dayRegex.enumerateMatches(in: html, options: [], range: fullRange) { match, _, _ in
            guard let match,
                  let dateRange = Range(match.range(at: 1), in: html),
                  let tagRange = Range(match.range, in: html) else { return }

            let dateString = String(html[dateRange])
            guard let date = dateFormatter.date(from: dateString) else { return }

            let tag = String(html[tagRange])
            guard tag.contains("ContributionCalendar-day") ||
                  tag.contains("data-level=") ||
                  tag.contains("data-count=") else {
                return
            }
            let tagNSRange = NSRange(tag.startIndex..<tag.endIndex, in: tag)

            // Extract data-level.
            var level: Int?
            if let levelMatch = levelRegex.firstMatch(in: tag, options: [], range: tagNSRange),
               let lvlRange = Range(levelMatch.range(at: 1), in: tag),
               let parsed = Int(tag[lvlRange]) {
                level = min(max(parsed, 0), 4)
            }

            // Prefer structured count attributes first, then aria-label, then tooltip lookup.
            var count: Int?
            if let countMatch = countRegex.firstMatch(in: tag, options: [], range: tagNSRange),
               let countRange = Range(countMatch.range(at: 1), in: tag) {
                let value = String(tag[countRange]).replacingOccurrences(of: ",", with: "")
                if let parsed = Int(value) {
                    count = max(0, parsed)
                }
            }

            if count == nil,
               let ariaMatch = ariaLabelRegex.firstMatch(in: tag, options: [], range: tagNSRange),
               let ariaRange = Range(ariaMatch.range(at: 1), in: tag) {
                count = Self.extractContributionCount(from: String(tag[ariaRange]))
            }

            if count == nil,
               let idMatch = idRegex.firstMatch(in: tag, options: [], range: tagNSRange),
               let idRange = Range(idMatch.range(at: 1), in: tag) {
                let elementId = String(tag[idRange])
                if let tipText = tooltips[elementId] {
                    count = Self.extractContributionCount(from: tipText)
                }
            }

            let resolvedCount = count ?? 0
            let resolvedLevel = level ?? Self.inferredContributionLevel(for: resolvedCount)
            let parsedDay = GitHubContributionDay(date: date, count: resolvedCount, level: resolvedLevel)

            // Prefer the richest entry when duplicates appear.
            if let existing = daysByDate[date] {
                let shouldReplace = parsedDay.count > existing.count ||
                    (parsedDay.count == existing.count && parsedDay.level > existing.level)
                if shouldReplace {
                    daysByDate[date] = parsedDay
                }
            } else {
                daysByDate[date] = parsedDay
            }
        }

        let results = daysByDate.values.sorted(by: { $0.date < $1.date })
        if results.isEmpty {
            throw GitHubContributionsServiceError.parseFailed
        }

        return results
    }

    private static func extractContributionCount(from text: String) -> Int {
        let normalized = plainText(fromHTML: text)
        let lowercased = normalized.lowercased()
        if lowercased.contains("no contributions") || lowercased.hasPrefix("no ") {
            return 0
        }

        if let contributionRange = normalized.range(
            of: #"([0-9][0-9,]*)\s+contributions?"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let matched = String(normalized[contributionRange])
            if let token = matched.split(separator: " ").first {
                let number = token.replacingOccurrences(of: ",", with: "")
                if let count = Int(number) {
                    return max(0, count)
                }
            }
        }

        if let token = normalized.components(separatedBy: CharacterSet.decimalDigits.inverted).first(where: { !$0.isEmpty }),
           let count = Int(token) {
            return max(0, count)
        }

        return 0
    }

    private static func extractAnnualTotal(from html: String) -> Int? {
        guard let range = html.range(
            of: #"([0-9][0-9,]*)\s+contributions?\s+in\s+the\s+last\s+year"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }

        let matched = String(html[range])
        guard let token = matched.split(separator: " ").first else {
            return nil
        }

        return Int(token.replacingOccurrences(of: ",", with: ""))
    }

    private static func inferredContributionLevel(for count: Int) -> Int {
        if count == 0 { return 0 }
        if count <= 2 { return 1 }
        if count <= 5 { return 2 }
        if count <= 9 { return 3 }
        return 4
    }

    private static func plainText(fromHTML html: String) -> String {
        let withoutTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let decoded = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        return decoded
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Grid builder

    private func buildHeatmap(
        for username: String,
        from days: [GitHubContributionDay],
        fetchedAt: Date,
        totalOverride: Int? = nil
    ) throws -> GitHubContributionHeatmap {
        let sortedDays = days.sorted(by: { $0.date < $1.date })
        guard let firstDay = sortedDays.first, let lastDay = sortedDays.last else {
            throw GitHubContributionsServiceError.parseFailed
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

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
        let todayDate = calendar.startOfDay(for: Date())
        var todayContributions = 0
        var hasExactToday = false
        var latestKnownDate: Date?
        var latestKnownCount = 0

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

            if normalizedDate == todayDate {
                todayContributions = day.count
                hasExactToday = true
            }

            if normalizedDate <= todayDate {
                if let currentLatest = latestKnownDate {
                    if normalizedDate > currentLatest {
                        latestKnownDate = normalizedDate
                        latestKnownCount = day.count
                    }
                } else {
                    latestKnownDate = normalizedDate
                    latestKnownCount = day.count
                }
            }
        }

        if !hasExactToday {
            print("No exact match for today \(todayDate). Using latest known count: \(latestKnownCount)")
            todayContributions = latestKnownCount
        }

        if let totalOverride, totalOverride > 0 {
            total = max(total, totalOverride)
        }

        return GitHubContributionHeatmap(
            username: username,
            weeks: weeks,
            totalContributions: total,
            todayContributions: todayContributions,
            fetchedAt: fetchedAt
        )
    }
}

// --- Main execution ---

@main
struct App {
    static func main() async {
        let service = GitHubContributionsService()
        let username = "torvalds" // A known user with contributions

        do {
            let heatmap = try await service.fetchHeatmap(for: username)
            print("Total: \(heatmap.totalContributions)")
            print("Today: \(heatmap.todayContributions)")
            print("Text: \(heatmap.totalOverTodayText)")
            
            // Debugging Today Logic
            let calendar = Calendar(identifier: .gregorian)
            let today = calendar.startOfDay(for: Date())
            print("Script considers today as: \(today)")
            
        } catch {
            print("Error: \(error)")
        }
    }
}
