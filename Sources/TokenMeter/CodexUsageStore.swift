import Foundation

final class CodexUsageStore {
    var onUpdate: ((CodexUsageSnapshot) -> Void)?

    private let sampler = CodexUsageSampler()
    private let accountUsageClient = CodexAccountUsageClient()
    private let accountUsageCache = CodexAccountUsageCache()
    private let rateLimitClient = CodexRateLimitClient()
    private let refreshQueue = DispatchQueue(label: "local.token-meter.refresh", qos: .utility)
    private var timer: Timer?
    private(set) var isRefreshing = false

    private(set) var snapshot = CodexUsageSnapshot.empty

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        onUpdate?(snapshot)

        refreshQueue.async { [weak self] in
            guard let self else { return }
            var nextSnapshot = self.sampler.snapshot()
            if let accountUsage = self.accountUsageCache.usageForToday(fetch: { self.accountUsageClient.readUsage() }) {
                nextSnapshot = nextSnapshot.applyingAccountUsage(accountUsage)
            }
            if let quota = self.rateLimitClient.readQuota() {
                nextSnapshot = nextSnapshot.applyingQuota(quota)
            }

            DispatchQueue.main.async {
                self.snapshot = nextSnapshot
                self.isRefreshing = false
                self.onUpdate?(nextSnapshot)
            }
        }
    }
}
