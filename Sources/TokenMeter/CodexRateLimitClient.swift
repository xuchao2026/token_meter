import Foundation

struct CodexQuotaSnapshot {
    let primaryWindow: UsageWindow
    let secondaryWindow: UsageWindow
    let planType: String?
    let fetchedAt: Date
}

final class CodexPlanTypeCache {
    private struct CachePayload: Codable {
        let planType: String
        let updatedAt: Date
    }

    private let cacheURL: URL

    init() {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        self.cacheURL = baseURL
            .appendingPathComponent("Token Meter", isDirectory: true)
            .appendingPathComponent("plan-type-cache.json")
    }

    func load() -> String? {
        guard let data = try? Data(contentsOf: cacheURL),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data) else {
            return nil
        }
        return normalized(payload.planType)
    }

    func update(with planType: String?) -> String? {
        guard let planType = normalized(planType) else {
            return load()
        }

        let payload = CachePayload(planType: planType, updatedAt: Date())
        guard let data = try? JSONEncoder().encode(payload) else { return planType }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? data.write(to: cacheURL, options: [.atomic])
        return planType
    }

    private func normalized(_ planType: String?) -> String? {
        guard let planType else { return nil }
        let trimmed = planType.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

final class CodexRateLimitClient {
    private let timeoutSeconds: TimeInterval = 12
    private let desktopCodexPath = "/Applications/Codex.app/Contents/Resources/codex"

    func readQuota() -> CodexQuotaSnapshot? {
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
                      let id = Self.number(message["id"]),
                      id == 2 else {
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
        send(["id": 2, "method": "account/rateLimits/read"], to: stdin)

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

    private func normalize(_ result: [String: Any]) -> CodexQuotaSnapshot? {
        let direct = result["rateLimits"] as? [String: Any]
        let byID = result["rateLimitsByLimitId"] as? [String: Any]
        let codex = byID?["codex"] as? [String: Any]
        let first = byID?.values.compactMap { $0 as? [String: Any] }.first
        guard let snapshot = codex ?? direct ?? first else { return nil }

        return CodexQuotaSnapshot(
            primaryWindow: parseWindow(snapshot["primary"] as? [String: Any]),
            secondaryWindow: parseWindow(snapshot["secondary"] as? [String: Any]),
            planType: snapshot["planType"] as? String,
            fetchedAt: Date()
        )
    }

    private func parseWindow(_ object: [String: Any]?) -> UsageWindow {
        guard let object else { return UsageWindow() }

        var resetsAt: Date?
        if let seconds = Self.double(object["resetsAt"]), seconds > 0 {
            resetsAt = Date(timeIntervalSince1970: seconds)
        }

        return UsageWindow(
            usedPercent: Self.double(object["usedPercent"]),
            windowMinutes: Int(Self.number(object["windowDurationMins"]) ?? 0),
            resetsAt: resetsAt
        )
    }

    private static func parseMessage(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func number(_ value: Any?) -> UInt64? {
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
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
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
