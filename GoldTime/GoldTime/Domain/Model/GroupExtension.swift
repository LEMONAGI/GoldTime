
import Foundation

// Domain 타입 — ScreenTimeManager Core 타입과 1:1 대응하며 Presentation/Data에서 사용
enum ExtensionSource: Equatable {
    case oneMinute
    case adReward
}

enum ExtensionFailure: Error, Equatable {
    case groupNotFound
    case oneMinuteLimitReached
    case relockTimerRegistrationFailed
}

struct GroupExtensionResult {
    let group: ScreenTimeGroup
    let durationSeconds: Int
    let overrideUntil: Date
    let remainingLockedGroups: [ScreenTimeGroup]
}
