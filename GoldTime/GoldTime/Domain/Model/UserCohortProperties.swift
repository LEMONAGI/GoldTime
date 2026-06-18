import Foundation

/// Firebase Analytics user property로 심을 코호트 축. 기존 이벤트(shield_hit, ad_unlock 등)를
/// 사용자 세그먼트별로 쪼개 보기 위한 데이터다.
///
/// - 개인정보 없이 **버킷/플래그**로만 구성한다(`RuleAnalyticsPayload`와 동일한 익명화 원칙).
/// - 기준 그룹은 `isApplied == true` 그룹 — 기존 `monitoring_synced`의 appliedGroupCount와
///   동일 기준이라 대시보드 간 일관성이 유지된다.
/// - Firebase 제약: property 이름 ≤24자, 값 ≤36자(아래 이름/값 모두 만족).
struct UserCohortProperties {
    /// 적용된 그룹 중 최빈 규칙. 동률·없음은 "none".
    let primaryRuleKind: String
    /// 적용된 그룹 수 버킷.
    let activeGroupCount: String
    let usesDaily: Bool
    let usesTimeWindow: Bool
    let usesCooldown: Bool

    init(groups: [ScreenTimeGroup]) {
        let applied = groups.filter { $0.isApplied }
        let kinds = applied.compactMap { $0.ruleKind }

        usesDaily = kinds.contains(.dailyLimit)
        usesTimeWindow = kinds.contains(.timeWindows)
        usesCooldown = kinds.contains(.cooldown)
        activeGroupCount = Self.activeGroupCountBucket(applied.count)
        primaryRuleKind = Self.primaryRuleKind(of: kinds)
    }

    /// `analyticsRepository.setUserProperty(value, for: name)`에 그대로 넘길 (이름, 값) 목록.
    var entries: [(name: String, value: String?)] {
        [
            ("primary_rule_kind", primaryRuleKind),
            ("active_group_count", activeGroupCount),
            ("uses_daily", String(usesDaily)),
            ("uses_timewindow", String(usesTimeWindow)),
            ("uses_cooldown", String(usesCooldown))
        ]
    }
}

private extension UserCohortProperties {
    static func activeGroupCountBucket(_ count: Int) -> String {
        switch count {
        case 0: return "count_0"
        case 1: return "count_1"
        case 2...3: return "count_2_3"
        default: return "count_4_plus"
        }
    }

    /// 최빈 규칙. 비어 있거나 최빈값이 둘 이상 동률이면 "none".
    static func primaryRuleKind(of kinds: [ScreenTimeGroup.RuleKind]) -> String {
        guard !kinds.isEmpty else { return "none" }
        let counts = Dictionary(grouping: kinds, by: { $0 }).mapValues { $0.count }
        let maxCount = counts.values.max() ?? 0
        let leaders = counts.filter { $0.value == maxCount }
        guard leaders.count == 1, let kind = leaders.keys.first else { return "none" }
        return kind.rawValue
    }
}
