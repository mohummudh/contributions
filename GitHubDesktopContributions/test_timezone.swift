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
    var totalOverTodayText: String { "\(totalContributions) / \(todayContributions)" }
}

// --- GitHubContributionsService Logic Extraction ---
// We extract the `buildHeatmap` logic to test it in isolation

class HeatmapBuilder {
    
    // Original Logic (simulated)
    static func buildHeatmapOriginal(
        for username: String,
        from days: [GitHubContributionDay],
        fetchedAt: Date,
        currentDate: Date // Injected for testing
    ) -> GitHubContributionHeatmap {
        let sortedDays = days.sorted(by: { $0.date < $1.date })
        guard let firstDay = sortedDays.first, let lastDay = sortedDays.last else {
            return GitHubContributionHeatmap(username: username, weeks: [], totalContributions: 0, todayContributions: 0, fetchedAt: fetchedAt)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let normalizedFirstDay = calendar.startOfDay(for: firstDay.date)
        let weekday = calendar.component(.weekday, from: normalizedFirstDay)
        let leadingPadding = (weekday - calendar.firstWeekday + 7) % 7
        let gridStartDay = calendar.date(byAdding: .day, value: -leadingPadding, to: normalizedFirstDay)!
        let normalizedLastDay = calendar.startOfDay(for: lastDay.date)
        let daySpan = calendar.dateComponents([.day], from: gridStartDay, to: normalizedLastDay).day!
        let weekCount = (daySpan / 7) + 1
        var weeks = Array(repeating: Array(repeating: GitHubContributionCell.empty, count: 7), count: weekCount)
        var total = 0
        
        // BUGGY LINE:
        let todayDate = calendar.startOfDay(for: currentDate)
        
        var todayContributions = 0
        var hasExactToday = false
        var latestKnownDate: Date?
        var latestKnownCount = 0

        for day in sortedDays {
            let normalizedDate = calendar.startOfDay(for: day.date)
            guard let offset = calendar.dateComponents([.day], from: gridStartDay, to: normalizedDate).day else { continue }
            guard offset >= 0 else { continue }
            let weekIndex = offset / 7
            let dayIndex = offset % 7
            if weekIndex < weeks.count && dayIndex < 7 {
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
        }
        
        if !hasExactToday {
            todayContributions = latestKnownCount
        }

        return GitHubContributionHeatmap(
            username: username,
            weeks: weeks,
            totalContributions: total,
            todayContributions: todayContributions,
            fetchedAt: fetchedAt
        )
    }

    // Proposed Fix Logic
    static func buildHeatmapFixed(
        for username: String,
        from days: [GitHubContributionDay],
        fetchedAt: Date,
        currentDate: Date
    ) -> GitHubContributionHeatmap {
        let sortedDays = days.sorted(by: { $0.date < $1.date })
        guard let firstDay = sortedDays.first, let lastDay = sortedDays.last else {
            return GitHubContributionHeatmap(username: username, weeks: [], totalContributions: 0, todayContributions: 0, fetchedAt: fetchedAt)
        }

        // Logic for Graph (GMT)
        var gmtCalendar = Calendar(identifier: .gregorian)
        gmtCalendar.firstWeekday = 1
        gmtCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let normalizedFirstDay = gmtCalendar.startOfDay(for: firstDay.date)
        let weekday = gmtCalendar.component(.weekday, from: normalizedFirstDay)
        let leadingPadding = (weekday - gmtCalendar.firstWeekday + 7) % 7
        let gridStartDay = gmtCalendar.date(byAdding: .day, value: -leadingPadding, to: normalizedFirstDay)!
        let normalizedLastDay = gmtCalendar.startOfDay(for: lastDay.date)
        let daySpan = gmtCalendar.dateComponents([.day], from: gridStartDay, to: normalizedLastDay).day!
        let weekCount = (daySpan / 7) + 1
        var weeks = Array(repeating: Array(repeating: GitHubContributionCell.empty, count: 7), count: weekCount)
        var total = 0
        
        // FIX: Determine "Today" using Device Current Calendar
        var deviceCalendar = Calendar.current // Will be simulated in test
        // Get Year/Month/Day from current date in device timezone
        let deviceComponents = deviceCalendar.dateComponents([.year, .month, .day], from: currentDate)
        // Construct the target date in GMT matching those components
        let todayDate = gmtCalendar.date(from: deviceComponents) ?? gmtCalendar.startOfDay(for: currentDate)
        
        var todayContributions = 0
        var hasExactToday = false
        var latestKnownDate: Date?
        var latestKnownCount = 0

        for day in sortedDays {
            let normalizedDate = gmtCalendar.startOfDay(for: day.date)
            guard let offset = gmtCalendar.dateComponents([.day], from: gridStartDay, to: normalizedDate).day else { continue }
            guard offset >= 0 else { continue }
            let weekIndex = offset / 7
            let dayIndex = offset % 7
            if weekIndex < weeks.count && dayIndex < 7 {
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
        }
        
        if !hasExactToday {
            todayContributions = latestKnownCount
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

// --- Test Execution ---
func runTest() {
    print("--- Starting TimeZone Logic Test ---")
    
    // Setup Dates
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC
    
    // Scenario:
    // User is in New York (UTC-5 in Winter).
    // Current Time: "2024-02-13 20:00:00 -0500" (8 PM)
    // In UTC this is: "2024-02-14 01:00:00 +0000" (1 AM next day)
    
    // Data has entry for "2024-02-13" with 10 contributions.
    // Data has entry for "2024-02-14" (future relative to user, but today relative to UTC) is NOT present or 0.
    
    guard let parsedDayDate = formatter.date(from: "2024-02-13 00:00:00") else { fatalError() }
    let days = [
        GitHubContributionDay(date: parsedDayDate, count: 10, level: 3)
    ]
    
    // Simulated "Current Date" (The Date() object)
    // Feb 14 01:00 UTC
    guard let simulatedNow = formatter.date(from: "2024-02-14 01:00:00") else { fatalError() }
    
    print("Data Date (GMT): \(parsedDayDate)")
    print("Current Time (UTC): \(simulatedNow)")
    
    // 1. Run Original Logic
    // Original logic forces GMT calendar for 'today'.
    // In GMT, Now is Feb 14.
    // Data is Feb 13.
    // Expected: todayDate = Feb 14. loop finds Feb 13. hasExactToday = False. latestKnown = Feb 13.
    // Result: 10.
    // WAIT. If latestKnown logic works, it should fall back to 10?
    // Let's trace:
    // normalizedDate (Feb 13) <= todayDate (Feb 14) -> True.
    // latestKnown becomes Feb 13 (count 10).
    // returns 10.
    
    let originalResult = HeatmapBuilder.buildHeatmapOriginal(for: "test", from: days, fetchedAt: Date(), currentDate: simulatedNow)
    print("Original Result Today: \(originalResult.todayContributions)")
    
    // Wait, if it returns 10, then why is the user complaining?
    // Maybe they have 0 on the *actual* day and it's showing previous day?
    // Scenario 2:
    // User has 5 contributions on Feb 13.
    // User has 0 contributions on Feb 14 (it's tomorrow for them!).
    // But in UTC it is Feb 14.
    // If the data *has* Feb 14 entry (0 contributions).
    
    guard let nextDayDate = formatter.date(from: "2024-02-14 00:00:00") else { fatalError() }
    let daysWithZeroNext = [
        GitHubContributionDay(date: parsedDayDate, count: 10, level: 3),
        GitHubContributionDay(date: nextDayDate, count: 0, level: 0)
    ]
    
    print("\nScenario 2: Data has Feb 13 (10) and Feb 14 (0). User is in NY (Feb 13 8PM). UTC is Feb 14 1AM.")
    
    let originalResult2 = HeatmapBuilder.buildHeatmapOriginal(for: "test", from: daysWithZeroNext, fetchedAt: Date(), currentDate: simulatedNow)
    print("Original Result (Scenario 2): \(originalResult2.todayContributions)")
    // Logic:
    // todayDate (GMT) = Feb 14.
    // Feb 13 <= Feb 14. Latest = Feb 13 (10).
    // Feb 14 <= Feb 14. Latest = Feb 14 (0).
    // Result: 0.
    // User expects: 10 (because it is Feb 13 for them).
    
    // 2. Run Fixed Logic
    // We need to Mock Calendar.current to be NY.
    // Swift doesn't allow easy global mock of Calendar.current, but in our Fixed function above we used `var deviceCalendar = Calendar.current`.
    // We can't easily injection-mock that class var in this script without modification.
    // So for this script, we will modify the Fixed function to accept a calendar or just manually simulate it inline.
    
    // Let's verify what the Fixed Logic DOES if we assume NY calendar.
    var nyCalendar = Calendar(identifier: .gregorian)
    nyCalendar.timeZone = TimeZone(identifier: "America/New_York")!
    
    // Fixed logic manual check:
    // deviceComponents from simulatedNow (Feb 14 01:00 UTC = Feb 13 20:00 NY) -> Year: 2024, Month: 2, Day: 13.
    let components = nyCalendar.dateComponents([.year, .month, .day], from: simulatedNow)
    print("User Local Date Components: \(components.year!)-\(components.month!)-\(components.day!)")
    
    // Construct todayDate in GMT using these components:
    var gmtCalendar = Calendar(identifier: .gregorian)
    gmtCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let fixedTodayDate = gmtCalendar.date(from: components)!
    print("Fixed Logic Target Date (GMT): \(fixedTodayDate)") // Should be Feb 13 00:00 GMT
    
    // Trace through data:
    // Feb 13 (10). == fixedTodayDate? YES. hasExactToday = True. todayContributions = 10.
    // Feb 14 (0). > fixedTodayDate? YES. (Ignored for today calcs, processed for grid).
    
    // So Fix should return 10.
    // Original returned 0.
    
    print("Fixed Logic Expected Result: 10")
}

runTest()
