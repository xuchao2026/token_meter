import Foundation

struct AccountUsageDailyBucket {
    let dayID: String
    let tokens: UInt64
}

struct CodexAccountUsageSnapshot {
    let lifetimeTokens: UInt64
    let peakDailyTokens: UInt64
    let longestRunningTurnSec: UInt64
    let currentStreakDays: Int
    let longestStreakDays: Int
    let dailyBuckets: [AccountUsageDailyBucket]
    let fetchedAt: Date
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
