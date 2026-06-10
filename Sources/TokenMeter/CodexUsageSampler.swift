import Foundation

struct TokenTotals {
    var inputTokens: UInt64 = 0
    var cachedInputTokens: UInt64 = 0
    var outputTokens: UInt64 = 0
    var reasoningOutputTokens: UInt64 = 0
    var totalTokens: UInt64 = 0

    static let zero = TokenTotals()

    mutating func add(_ other: TokenTotals) {
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        outputTokens += other.outputTokens
        reasoningOutputTokens += other.reasoningOutputTokens
        totalTokens += other.totalTokens
    }

    func subtractingFloorZero(_ previous: TokenTotals) -> TokenTotals {
        TokenTotals(
            inputTokens: inputTokens >= previous.inputTokens ? inputTokens - previous.inputTokens : inputTokens,
            cachedInputTokens: cachedInputTokens >= previous.cachedInputTokens ? cachedInputTokens - previous.cachedInputTokens : cachedInputTokens,
            outputTokens: outputTokens >= previous.outputTokens ? outputTokens - previous.outputTokens : outputTokens,
            reasoningOutputTokens: reasoningOutputTokens >= previous.reasoningOutputTokens ? reasoningOutputTokens - previous.reasoningOutputTokens : reasoningOutputTokens,
            totalTokens: totalTokens >= previous.totalTokens ? totalTokens - previous.totalTokens : totalTokens
        )
    }
}

struct UsageWindow {
    var usedPercent: Double?
    var windowMinutes: Int?
    var resetsAt: Date?

    var remainingPercent: Double? {
        guard let usedPercent else { return nil }
        return max(0, min(100, 100 - usedPercent))
    }
}

struct DailyUsagePoint {
    let dayID: String
    let label: String
    let totals: TokenTotals
}

struct UsageCategory {
    let name: String
    let tokens: UInt64
    let share: Double
}

struct CodexUsageSnapshot {
    let generatedAt: Date
    let today: TokenTotals
    let yesterday: TokenTotals
    let sevenDays: TokenTotals
    let month: TokenTotals
    let allTime: TokenTotals
    let lastTurn: TokenTotals
    let primaryWindow: UsageWindow
    let secondaryWindow: UsageWindow
    let planType: String?
    let quotaFetchedAt: Date?
    let modelContextWindow: UInt64
    let eventCount: Int
    let fileCount: Int
    let history: [DailyUsagePoint]
    let categories: [UsageCategory]
    let peakDailyTokens: UInt64?
    let longestRunningTurnSec: UInt64?
    let currentStreakDays: Int?
    let longestStreakDays: Int?
    let accountUsageFetchedAt: Date?

    static let empty = CodexUsageSnapshot(
        generatedAt: Date(),
        today: .zero,
        yesterday: .zero,
        sevenDays: .zero,
        month: .zero,
        allTime: .zero,
        lastTurn: .zero,
        primaryWindow: UsageWindow(),
        secondaryWindow: UsageWindow(),
        planType: nil,
        quotaFetchedAt: nil,
        modelContextWindow: 0,
        eventCount: 0,
        fileCount: 0,
        history: [],
        categories: [],
        peakDailyTokens: nil,
        longestRunningTurnSec: nil,
        currentStreakDays: nil,
        longestStreakDays: nil,
        accountUsageFetchedAt: nil
    )

    func applyingQuota(_ quota: CodexQuotaSnapshot) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            generatedAt: generatedAt,
            today: today,
            yesterday: yesterday,
            sevenDays: sevenDays,
            month: month,
            allTime: allTime,
            lastTurn: lastTurn,
            primaryWindow: quota.primaryWindow,
            secondaryWindow: quota.secondaryWindow,
            planType: quota.planType,
            quotaFetchedAt: quota.fetchedAt,
            modelContextWindow: modelContextWindow,
            eventCount: eventCount,
            fileCount: fileCount,
            history: history,
            categories: categories,
            peakDailyTokens: peakDailyTokens,
            longestRunningTurnSec: longestRunningTurnSec,
            currentStreakDays: currentStreakDays,
            longestStreakDays: longestStreakDays,
            accountUsageFetchedAt: accountUsageFetchedAt
        )
    }

    func applyingAccountUsage(_ accountUsage: CodexAccountUsageSnapshot) -> CodexUsageSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "zh_CN")
        dayFormatter.timeZone = .current
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let labelFormatter = DateFormatter()
        labelFormatter.calendar = calendar
        labelFormatter.locale = Locale(identifier: "zh_CN")
        labelFormatter.timeZone = .current
        labelFormatter.dateFormat = "M/d"

        let now = Date()
        let todayID = dayFormatter.string(from: now)
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterdayID = dayFormatter.string(from: yesterdayDate)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? calendar.startOfDay(for: now)
        var bucketsByDay: [String: UInt64] = [:]
        for bucket in accountUsage.dailyBuckets {
            bucketsByDay[bucket.dayID, default: 0] += bucket.tokens
        }
        if today.totalTokens > 0 {
            bucketsByDay[todayID] = today.totalTokens
        }

        func totals(_ tokens: UInt64) -> TokenTotals {
            var result = TokenTotals.zero
            result.totalTokens = tokens
            return result
        }

        func tokens(for dayID: String) -> UInt64 {
            bucketsByDay[dayID] ?? 0
        }

        let history = (0..<7).reversed().compactMap { offset -> DailyUsagePoint? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let dayID = dayFormatter.string(from: date)
            return DailyUsagePoint(
                dayID: dayID,
                label: labelFormatter.string(from: date),
                totals: totals(tokens(for: dayID))
            )
        }

        var sevenDays = TokenTotals.zero
        history.forEach { sevenDays.add($0.totals) }

        var month = TokenTotals.zero
        for (dayID, tokens) in bucketsByDay {
            guard let date = dayFormatter.date(from: dayID), date >= monthStart else { continue }
            month.add(totals(tokens))
        }

        return CodexUsageSnapshot(
            generatedAt: generatedAt,
            today: today.totalTokens > 0 ? today : totals(tokens(for: todayID)),
            yesterday: totals(tokens(for: yesterdayID)),
            sevenDays: sevenDays,
            month: month,
            allTime: totals(accountUsage.lifetimeTokens),
            lastTurn: lastTurn,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            planType: planType,
            quotaFetchedAt: quotaFetchedAt,
            modelContextWindow: modelContextWindow,
            eventCount: accountUsage.dailyBuckets.count,
            fileCount: fileCount,
            history: history,
            categories: categories,
            peakDailyTokens: accountUsage.peakDailyTokens,
            longestRunningTurnSec: accountUsage.longestRunningTurnSec,
            currentStreakDays: accountUsage.currentStreakDays,
            longestStreakDays: accountUsage.longestStreakDays,
            accountUsageFetchedAt: accountUsage.fetchedAt
        )
    }
}

struct CodexUsageSampler {
    private let codexHome: URL
    private let calendar: Calendar
    private let isoFormatter: ISO8601DateFormatter
    private let dayFormatter: DateFormatter
    private let monthFormatter: DateFormatter
    private let labelFormatter: DateFormatter

    init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        self.codexHome = codexHome

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        self.calendar = calendar

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = isoFormatter

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "zh_CN")
        dayFormatter.timeZone = .current
        dayFormatter.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = dayFormatter

        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.locale = Locale(identifier: "zh_CN")
        monthFormatter.timeZone = .current
        monthFormatter.dateFormat = "yyyy-MM"
        self.monthFormatter = monthFormatter

        let labelFormatter = DateFormatter()
        labelFormatter.calendar = calendar
        labelFormatter.locale = Locale(identifier: "zh_CN")
        labelFormatter.timeZone = .current
        labelFormatter.dateFormat = "M/d"
        self.labelFormatter = labelFormatter
    }

    func snapshot() -> CodexUsageSnapshot {
        let files = usageFiles()
        var records: [UsageRecord] = []
        var totalsByDay: [String: TokenTotals] = [:]
        var allTime = TokenTotals.zero
        var eventCount = 0
        var newestEventDate = Date.distantPast
        var lastTurn = TokenTotals.zero
        var primaryWindow = UsageWindow()
        var secondaryWindow = UsageWindow()
        var modelContextWindow: UInt64 = 0

        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            var previousCumulative: TokenTotals?

            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard line.contains("\"token_count\""),
                      let event = parseTokenEvent(String(line)) else {
                    continue
                }

                let usage = event.incrementalUsage(previousCumulative: previousCumulative)
                if let totalUsage = event.totalUsage {
                    previousCumulative = totalUsage
                }

                let dayID = dayFormatter.string(from: event.timestamp)
                totalsByDay[dayID, default: .zero].add(usage)
                allTime.add(usage)
                records.append(UsageRecord(timestamp: event.timestamp, usage: usage))
                eventCount += 1

                if event.timestamp >= newestEventDate {
                    newestEventDate = event.timestamp
                    lastTurn = usage
                    primaryWindow = event.primaryWindow
                    secondaryWindow = event.secondaryWindow
                    modelContextWindow = event.modelContextWindow
                }
            }
        }

        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? todayStart
        let sevenDaysStart = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let todayID = dayFormatter.string(from: now)
        let yesterdayID = dayFormatter.string(from: calendar.date(byAdding: .day, value: -1, to: now) ?? now)
        let history = lastSevenDays(endingAt: now).map { date in
            let dayID = dayFormatter.string(from: date)
            return DailyUsagePoint(dayID: dayID, label: labelFormatter.string(from: date), totals: totalsByDay[dayID] ?? .zero)
        }

        var today = TokenTotals.zero
        var yesterday = TokenTotals.zero
        var sevenDays = TokenTotals.zero
        var month = TokenTotals.zero
        for record in records {
            if record.timestamp >= todayStart {
                today.add(record.usage)
            } else if record.timestamp >= yesterdayStart, record.timestamp < todayStart {
                yesterday.add(record.usage)
            }
            if record.timestamp >= sevenDaysStart {
                sevenDays.add(record.usage)
            }
            if record.timestamp >= monthStart {
                month.add(record.usage)
            }
        }

        return CodexUsageSnapshot(
            generatedAt: now,
            today: today.totalTokens > 0 ? today : (totalsByDay[todayID] ?? .zero),
            yesterday: yesterday.totalTokens > 0 ? yesterday : (totalsByDay[yesterdayID] ?? .zero),
            sevenDays: sevenDays,
            month: month,
            allTime: allTime,
            lastTurn: lastTurn,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            planType: nil,
            quotaFetchedAt: nil,
            modelContextWindow: modelContextWindow,
            eventCount: eventCount,
            fileCount: files.count,
            history: history,
            categories: categories(for: month),
            peakDailyTokens: nil,
            longestRunningTurnSec: nil,
            currentStreakDays: nil,
            longestStreakDays: nil,
            accountUsageFetchedAt: nil
        )
    }

    private func usageFiles() -> [URL] {
        let roots = [
            codexHome.appendingPathComponent("sessions"),
            codexHome.appendingPathComponent("archived_sessions")
        ]
        var files: [URL] = []

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                files.append(file)
            }
        }

        return files
    }

    private func parseTokenEvent(_ line: String) -> TokenEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "event_msg",
              let timestampString = object["timestamp"] as? String,
              let timestamp = parseDate(timestampString),
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any] else {
            return nil
        }

        let lastUsage = (info["last_token_usage"] as? [String: Any]).map(parseUsage)
        let totalUsage = (info["total_token_usage"] as? [String: Any]).map(parseUsage)
        guard lastUsage != nil || totalUsage != nil else { return nil }

        let rateLimits = payload["rate_limits"] as? [String: Any]
        return TokenEvent(
            timestamp: timestamp,
            lastUsage: lastUsage,
            totalUsage: totalUsage,
            primaryWindow: parseWindow(rateLimits?["primary"] as? [String: Any]),
            secondaryWindow: parseWindow(rateLimits?["secondary"] as? [String: Any]),
            modelContextWindow: number(info["model_context_window"])
        )
    }

    private func parseDate(_ value: String) -> Date? {
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }

    private func parseUsage(_ object: [String: Any]) -> TokenTotals {
        TokenTotals(
            inputTokens: number(object["input_tokens"]),
            cachedInputTokens: number(object["cached_input_tokens"]),
            outputTokens: number(object["output_tokens"]),
            reasoningOutputTokens: number(object["reasoning_output_tokens"]),
            totalTokens: number(object["total_tokens"])
        )
    }

    private func parseWindow(_ object: [String: Any]?) -> UsageWindow {
        guard let object else { return UsageWindow() }

        var resetsAt: Date?
        if let seconds = double(object["resets_at"]), seconds > 0 {
            resetsAt = Date(timeIntervalSince1970: seconds)
        }

        return UsageWindow(
            usedPercent: double(object["used_percent"]),
            windowMinutes: Int(number(object["window_minutes"])),
            resetsAt: resetsAt
        )
    }

    private func categories(for totals: TokenTotals) -> [UsageCategory] {
        let cached = min(totals.cachedInputTokens, totals.inputTokens)
        let freshInput = totals.inputTokens - cached
        let reasoning = min(totals.reasoningOutputTokens, totals.outputTokens)
        let visibleOutput = totals.outputTokens - reasoning

        let rows = [
            ("新输入", freshInput),
            ("缓存输入", cached),
            ("可见输出", visibleOutput),
            ("推理输出", reasoning)
        ]
        let categoryTotal = max(rows.reduce(UInt64(0)) { $0 + $1.1 }, 1)

        return rows.map { name, tokens in
            UsageCategory(name: name, tokens: tokens, share: Double(tokens) / Double(categoryTotal))
        }
    }

    private func lastSevenDays(endingAt date: Date) -> [Date] {
        (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: date)
        }
    }

    private func number(_ value: Any?) -> UInt64 {
        if let number = value as? NSNumber {
            return number.uint64Value
        }
        if let int = value as? Int {
            return UInt64(max(0, int))
        }
        if let double = value as? Double {
            return UInt64(max(0, double))
        }
        if let string = value as? String, let double = Double(string) {
            return UInt64(max(0, double))
        }
        return 0
    }

    private func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }
}

private struct TokenEvent {
    let timestamp: Date
    let lastUsage: TokenTotals?
    let totalUsage: TokenTotals?
    let primaryWindow: UsageWindow
    let secondaryWindow: UsageWindow
    let modelContextWindow: UInt64

    func incrementalUsage(previousCumulative: TokenTotals?) -> TokenTotals {
        if let lastUsage {
            return lastUsage
        }
        guard let totalUsage else { return .zero }
        guard let previousCumulative else { return totalUsage }
        return totalUsage.subtractingFloorZero(previousCumulative)
    }
}

private struct UsageRecord {
    let timestamp: Date
    let usage: TokenTotals
}
