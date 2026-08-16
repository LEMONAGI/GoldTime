
import Foundation

final class AnalyticsRepositoryImpl: AnalyticsRepository {
    private struct StrictLockCommitment: Codable {
        let groupID: UUID
        let startedAt: Date
        let expiresAt: Date
    }

    private static let strictLockCommitmentsKey = "analytics.strictLockCommitments"

    private let service: AnalyticsService
    private let userDefaults: UserDefaults

    init(service: AnalyticsService = .shared, userDefaults: UserDefaults = .standard) {
        self.service = service
        self.userDefaults = userDefaults
    }

    func log(_ event: AnalyticsEvent) {
        service.logEvent(name: event.name, parameters: event.parameters)
    }

    func setUserProperty(_ value: String?, for name: String) {
        service.setUserProperty(value, for: name)
    }

    func recordError(_ error: Error, context: String) {
        service.recordError(error, context: context)
    }

    func recordStrictLockCommitment(groupID: UUID, startedAt: Date, expiresAt: Date) {
        var commitments = strictLockCommitments.filter { $0.groupID != groupID }
        commitments.append(
            StrictLockCommitment(groupID: groupID, startedAt: startedAt, expiresAt: expiresAt)
        )
        strictLockCommitments = commitments
    }

    func discardStrictLockCommitments(groupIDs: [UUID]) {
        let discarded = Set(groupIDs)
        guard !discarded.isEmpty else { return }
        strictLockCommitments = strictLockCommitments.filter { !discarded.contains($0.groupID) }
    }

    func discardAllStrictLockCommitments() {
        userDefaults.removeObject(forKey: Self.strictLockCommitmentsKey)
    }

    func drainCompletedStrictLockDays(at now: Date) -> [Int] {
        let commitments = strictLockCommitments
        let completed = commitments.filter { $0.expiresAt <= now }
        strictLockCommitments = commitments.filter { $0.expiresAt > now }
        return completed.map { commitment in
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: commitment.startedAt)
            return max(1, calendar.dateComponents([.day], from: start, to: commitment.expiresAt).day ?? 1)
        }
    }

    private var strictLockCommitments: [StrictLockCommitment] {
        get {
            guard let data = userDefaults.data(forKey: Self.strictLockCommitmentsKey) else { return [] }
            return (try? JSONDecoder().decode([StrictLockCommitment].self, from: data)) ?? []
        }
        set {
            guard !newValue.isEmpty else {
                userDefaults.removeObject(forKey: Self.strictLockCommitmentsKey)
                return
            }
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults.set(data, forKey: Self.strictLockCommitmentsKey)
        }
    }
}
