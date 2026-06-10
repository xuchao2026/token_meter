import Foundation

enum Formatters {
    static func bytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(value)) \(units[unitIndex])"
        }

        let decimals = value >= 100 ? 0 : (value >= 10 ? 1 : 2)
        return String(format: "%.\(decimals)f %@", value, units[unitIndex])
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        bytes(UInt64(max(0, bytesPerSecond))) + "/s"
    }

    static func percent(_ value: Double) -> String {
        "\(Int(round(max(0, min(value, 1)) * 100)))%"
    }

    static func usedPercent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(round(max(0, min(value, 100)))))%"
    }

    static func remainingPercent(_ window: UsageWindow) -> String {
        usedPercent(window.remainingPercent)
    }

    static func tokens(_ tokens: UInt64) -> String {
        if tokens >= 100_000_000 {
            let value = Double(tokens) / 100_000_000
            return oneDecimal(value) + "亿"
        }
        if tokens >= 10_000 {
            let value = Double(tokens) / 10_000
            if value >= 100 {
                return "\(Int(round(value)))万"
            }
            return oneDecimal(value) + "万"
        }
        return tokens.formatted()
    }

    static func rawTokens(_ tokens: UInt64) -> String {
        tokens.formatted()
    }

    static func resetTime(_ date: Date?) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current

        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "M/d HH:mm"
        }
        return formatter.string(from: date)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval / 60))
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return "\(days) 天 \(hours) 小时"
        }
        if hours > 0 {
            return "\(hours) 小时 \(minutes) 分钟"
        }
        return "\(minutes) 分钟"
    }

    private static func oneDecimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }
}
