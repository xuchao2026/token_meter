import CoreGraphics
import Foundation

final class CodexUsageStore {
    var onUpdate: ((CodexUsageSnapshot) -> Void)?

    private let sampler = CodexUsageSampler()
    private let accountUsageClient = CodexAccountUsageClient()
    private let accountUsageCache = CodexAccountUsageCache()
    private let rateLimitClient = CodexRateLimitClient()
    private let planTypeCache = CodexPlanTypeCache()
    private let refreshQueue = DispatchQueue(label: "local.token-meter.refresh", qos: .utility)
    private let automaticRefreshInterval: TimeInterval = 60
    private let mouseIdleThreshold: TimeInterval = 5 * 60
    private var timer: Timer?
    private var cachedPlanType: String?
    private(set) var isRefreshing = false

    private(set) var snapshot = CodexUsageSnapshot.empty

    init() {
        cachedPlanType = planTypeCache.load()
    }

    func start() {
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        timer?.invalidate()
        timer = nil
        refresh(isAutomatic: false)
    }

    private func refresh(isAutomatic _: Bool) {
        guard !isRefreshing else { return }
        isRefreshing = true
        onUpdate?(snapshot)

        refreshQueue.async { [weak self] in
            guard let self else { return }
            var nextSnapshot = self.sampler.snapshot().applyingPlanType(self.cachedPlanType)
            if let accountUsage = self.accountUsageCache.usageForToday(fetch: { self.accountUsageClient.readUsage() }) {
                nextSnapshot = nextSnapshot.applyingAccountUsage(accountUsage)
            }
            if let quota = self.rateLimitClient.readQuota() {
                self.cachedPlanType = self.planTypeCache.update(with: quota.planType) ?? self.cachedPlanType
                nextSnapshot = nextSnapshot.applyingQuota(quota)
            }
            nextSnapshot = nextSnapshot.applyingPlanType(self.cachedPlanType)

            DispatchQueue.main.async {
                self.snapshot = nextSnapshot
                self.isRefreshing = false
                self.onUpdate?(nextSnapshot)
                self.scheduleNextAutomaticRefresh(using: nextSnapshot)
            }
        }
    }

    private func scheduleNextAutomaticRefresh(using snapshot: CodexUsageSnapshot) {
        timer?.invalidate()
        let plan = nextAutomaticRefreshPlan(using: snapshot)
        let interval = max(1, plan.date.timeIntervalSinceNow)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.timer = nil
            if plan.reason == .regularCadence, !self.isMouseRecentlyActive() {
                self.scheduleNextAutomaticRefresh(using: self.snapshot)
                return
            }
            self.refresh(isAutomatic: true)
        }
    }

    private func nextAutomaticRefreshPlan(using snapshot: CodexUsageSnapshot) -> AutomaticRefreshPlan {
        let now = Date()
        let exhaustedResetDates = [
            resetDateIfExhausted(snapshot.primaryWindow),
            resetDateIfExhausted(snapshot.secondaryWindow)
        ].compactMap { $0 }

        guard !exhaustedResetDates.isEmpty else {
            return AutomaticRefreshPlan(date: now.addingTimeInterval(automaticRefreshInterval), reason: .regularCadence)
        }

        let resetDate = exhaustedResetDates.min() ?? now.addingTimeInterval(automaticRefreshInterval)
        if resetDate <= now {
            return AutomaticRefreshPlan(date: now.addingTimeInterval(automaticRefreshInterval), reason: .regularCadence)
        }
        return AutomaticRefreshPlan(date: resetDate.addingTimeInterval(1), reason: .quotaReset)
    }

    private func resetDateIfExhausted(_ window: UsageWindow) -> Date? {
        guard let remaining = window.remainingPercent,
              remaining <= 0 else {
            return nil
        }
        return window.resetsAt ?? Date().addingTimeInterval(automaticRefreshInterval)
    }

    private func isMouseRecentlyActive() -> Bool {
        recentMouseIdleSeconds() < mouseIdleThreshold
    }

    private func recentMouseIdleSeconds() -> TimeInterval {
        let sourceState = CGEventSourceStateID.combinedSessionState
        let eventTypes: [CGEventType] = [
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .scrollWheel
        ]
        return eventTypes
            .map { CGEventSource.secondsSinceLastEventType(sourceState, eventType: $0) }
            .min() ?? TimeInterval.greatestFiniteMagnitude
    }
}

private struct AutomaticRefreshPlan {
    let date: Date
    let reason: AutomaticRefreshReason
}

private enum AutomaticRefreshReason {
    case regularCadence
    case quotaReset
}
