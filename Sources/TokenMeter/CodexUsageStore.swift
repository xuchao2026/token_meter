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
        let nextDate = nextAutomaticRefreshDate(using: snapshot)
        let interval = max(1, nextDate.timeIntervalSinceNow)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.timer = nil
            self.refresh(isAutomatic: true)
        }
    }

    private func nextAutomaticRefreshDate(using snapshot: CodexUsageSnapshot) -> Date {
        let now = Date()
        let exhaustedResetDates = [
            resetDateIfExhausted(snapshot.primaryWindow),
            resetDateIfExhausted(snapshot.secondaryWindow)
        ].compactMap { $0 }

        guard !exhaustedResetDates.isEmpty else {
            return now.addingTimeInterval(automaticRefreshInterval)
        }

        let resetDate = exhaustedResetDates.min() ?? now.addingTimeInterval(automaticRefreshInterval)
        if resetDate <= now {
            return now.addingTimeInterval(automaticRefreshInterval)
        }
        return resetDate.addingTimeInterval(1)
    }

    private func resetDateIfExhausted(_ window: UsageWindow) -> Date? {
        guard let remaining = window.remainingPercent,
              remaining <= 0 else {
            return nil
        }
        return window.resetsAt ?? Date().addingTimeInterval(automaticRefreshInterval)
    }
}
