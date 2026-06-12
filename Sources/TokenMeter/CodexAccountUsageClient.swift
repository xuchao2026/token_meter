import Foundation

struct AccountUsageDailyBucket: Codable {
    let dayID: String
    let tokens: UInt64
}

struct CodexAccountUsageSnapshot: Codable {
    let lifetimeTokens: UInt64
    let peakDailyTokens: UInt64
    let longestRunningTurnSec: UInt64
    let currentStreakDays: Int
    let longestStreakDays: Int
    let dailyBuckets: [AccountUsageDailyBucket]
    let fetchedAt: Date
}

final class CodexAccountUsageCache {
    private struct CachePayload: Codable {
        let cacheDayID: String
        let snapshot: CodexAccountUsageSnapshot
    }

    private let retryInterval: TimeInterval = 10 * 60
    private let dayFormatter: DateFormatter
    private let cacheURL: URL
    private var lastAttemptDayID: String?
    private var lastAttemptAt: Date?

    init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "zh_CN")
        dayFormatter.timeZone = .current
        dayFormatter.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = dayFormatter

        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        self.cacheURL = baseURL
            .appendingPathComponent("Token Meter", isDirectory: true)
            .appendingPathComponent("account-usage-cache.json")
    }

    func usageForToday(fetch: () -> CodexAccountUsageSnapshot?) -> CodexAccountUsageSnapshot? {
        let now = Date()
        let todayID = dayFormatter.string(from: now)
        let cachedPayload = loadPayload()
        let cachedSnapshot = cachedPayload?.snapshot

        if shouldAttemptFetch(for: todayID, now: now),
           let freshSnapshot = fetch() {
            let mergedSnapshot = merge(cached: cachedSnapshot, fresh: freshSnapshot)
            save(snapshot: mergedSnapshot, cacheDayID: todayID)
            return mergedSnapshot
        }

        return cachedSnapshot
    }

    private func shouldAttemptFetch(for todayID: String, now: Date) -> Bool {
        guard lastAttemptDayID == todayID, let lastAttemptAt else {
            lastAttemptDayID = todayID
            lastAttemptAt = now
            return true
        }

        if now.timeIntervalSince(lastAttemptAt) >= retryInterval {
            self.lastAttemptAt = now
            return true
        }
        return false
    }

    private func loadPayload() -> CachePayload? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(CachePayload.self, from: data)
    }

    private func save(snapshot: CodexAccountUsageSnapshot, cacheDayID: String) {
        let payload = CachePayload(cacheDayID: cacheDayID, snapshot: snapshot)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? data.write(to: cacheURL, options: [.atomic])
    }

    private func merge(cached: CodexAccountUsageSnapshot?, fresh: CodexAccountUsageSnapshot) -> CodexAccountUsageSnapshot {
        guard let cached else { return fresh }

        var bucketsByDay: [String: UInt64] = [:]
        for bucket in cached.dailyBuckets {
            bucketsByDay[bucket.dayID] = max(bucketsByDay[bucket.dayID] ?? 0, bucket.tokens)
        }
        for bucket in fresh.dailyBuckets {
            bucketsByDay[bucket.dayID] = max(bucketsByDay[bucket.dayID] ?? 0, bucket.tokens)
        }

        let buckets = bucketsByDay
            .map { AccountUsageDailyBucket(dayID: $0.key, tokens: $0.value) }
            .sorted { $0.dayID < $1.dayID }

        return CodexAccountUsageSnapshot(
            lifetimeTokens: max(cached.lifetimeTokens, fresh.lifetimeTokens),
            peakDailyTokens: max(cached.peakDailyTokens, fresh.peakDailyTokens),
            longestRunningTurnSec: max(cached.longestRunningTurnSec, fresh.longestRunningTurnSec),
            currentStreakDays: fresh.currentStreakDays > 0 ? fresh.currentStreakDays : cached.currentStreakDays,
            longestStreakDays: max(cached.longestStreakDays, fresh.longestStreakDays),
            dailyBuckets: buckets,
            fetchedAt: fresh.fetchedAt
        )
    }
}

final class CodexAccountUsageClient {
    private let timeoutSeconds: TimeInterval = 12
    private let desktopCodexPath = "/Applications/Codex.app/Contents/Resources/codex"

    func readUsage() -> CodexAccountUsageSnapshot? {
        let process = Process()
        if FileManager.default.fileExists(atPath: desktopCodexPath) {
            process.executableURL = URL(fileURLWithPath: desktopCodexPath)
            process.arguments = ["app-server", "--listen", "stdio://"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["codex", "app-server", "--listen", "stdio://"]
        }

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let lock = NSLock()
        let complete = DispatchSemaphore(value: 0)
        var buffer = Data()
        var result: [String: Any]?
        var completed = false

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            lock.lock()
            buffer.append(data)
            while let newlineIndex = buffer.firstIndex(of: 10) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineIndex)
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
                guard let message = Self.parseMessage(lineData),
                      Self.number(message["id"]) == 2 else {
                    continue
                }

                result = message["result"] as? [String: Any]
                if !completed {
                    completed = true
                    complete.signal()
                }
            }
            lock.unlock()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        send(
            [
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "token-meter",
                        "title": "Token Meter",
                        "version": "0.1.0"
                    ],
                    "capabilities": NSNull()
                ]
            ],
            to: stdin
        )
        send(["id": 2, "method": "account/usage/read"], to: stdin)

        let status = complete.wait(timeout: .now() + timeoutSeconds)
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }

        guard status == .success, let result else { return nil }
        return normalize(result)
    }

    private func send(_ object: [String: Any], to pipe: Pipe) {
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object) else {
            return
        }
        data.append(10)
        try? pipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func normalize(_ result: [String: Any]) -> CodexAccountUsageSnapshot? {
        guard let summary = result["summary"] as? [String: Any] else { return nil }
        let buckets = (result["dailyUsageBuckets"] as? [[String: Any]] ?? [])
            .compactMap { bucket -> AccountUsageDailyBucket? in
                guard let dayID = bucket["startDate"] as? String else { return nil }
                return AccountUsageDailyBucket(dayID: dayID, tokens: Self.number(bucket["tokens"]))
            }
            .sorted { $0.dayID < $1.dayID }

        return CodexAccountUsageSnapshot(
            lifetimeTokens: Self.number(summary["lifetimeTokens"]),
            peakDailyTokens: Self.number(summary["peakDailyTokens"]),
            longestRunningTurnSec: Self.number(summary["longestRunningTurnSec"]),
            currentStreakDays: Int(Self.number(summary["currentStreakDays"])),
            longestStreakDays: Int(Self.number(summary["longestStreakDays"])),
            dailyBuckets: buckets,
            fetchedAt: Date()
        )
    }

    private static func parseMessage(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func number(_ value: Any?) -> UInt64 {
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
}
