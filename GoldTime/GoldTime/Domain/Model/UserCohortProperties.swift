import Foundation

/// Firebase Analytics user property로 심을 코호트 축. 기존 이벤트(shield_hit, ad_unlock 등)를
/// 사용자 세그먼트별로 쪼개 보기 위한 데이터다.
///
/// - 개인정보 없이 **버킷/플래그**로만 구성한다(`RuleAnalyticsPayload`와 동일한 익명화 원칙).
/// - 기준 그룹은 `isApplied == true` 그룹 — 기존 `monitoring_synced`의 appliedGroupCount와
///   동일 기준이라 대시보드 간 일관성이 유지된다.
/// - Firebase 제약: property 이름 ≤24자, 값 ≤36자(아래 이름/값 모두 만족).
struct UserCohortProperties {
    /// 적용된 그룹 중 최빈 규칙(그룹당 1표 — 요일별 그룹은 "weekday"). 동률·없음은 "none".
    let primaryRuleKind: String
    /// 적용된 그룹 수 버킷.
    let activeGroupCount: String
    let usesDaily: Bool
    let usesTimeWindow: Bool
    let usesCooldown: Bool
    /// 요일별 규칙을 쓰는 적용 그룹이 하나라도 있는지.
    let usesWeekday: Bool

    init(groups: [ScreenTimeGroup]) {
        let applied = groups.filter { $0.isApplied }
        // uses* 플래그는 요일별 그룹의 요일 안에서 쓰는 종류까지 포함한다
        // (예: 평일 쿨다운 + 주말 제한 없음 → usesCooldown true). base ruleKind는 요일별
        // 그룹에서 폴백용이므로 세지 않는다.
        let kinds: Set<ScreenTimeGroup.RuleKind> = applied.reduce(into: []) { result, group in
            if let rules = group.weekdayRules {
                for day in rules {
                    switch day.kind {
                    case .unrestricted: break
                    case .dailyLimit: result.insert(.dailyLimit)
                    case .timeWindows: result.insert(.timeWindows)
                    case .cooldown: result.insert(.cooldown)
                    }
                }
            } else if let kind = group.ruleKind {
                result.insert(kind)
            }
        }

        usesDaily = kinds.contains(.dailyLimit)
        usesTimeWindow = kinds.contains(.timeWindows)
        usesCooldown = kinds.contains(.cooldown)
        usesWeekday = applied.contains { $0.usesWeekdayRules }
        activeGroupCount = Self.activeGroupCountBucket(applied.count)
        // 최빈 규칙은 그룹당 1표 유지 — 요일별 그룹이 요일 수만큼 표를 갖게 하면 분포가 왜곡된다.
        primaryRuleKind = Self.primaryRuleKind(
            of: applied.map { $0.usesWeekdayRules ? "weekday" : ($0.ruleKind?.rawValue ?? "none") }
        )
    }

    /// `analyticsRepository.setUserProperty(value, for: name)`에 그대로 넘길 (이름, 값) 목록.
    var entries: [(name: String, value: String?)] {
        [
            ("primary_rule_kind", primaryRuleKind),
            ("active_group_count", activeGroupCount),
            ("uses_daily", String(usesDaily)),
            ("uses_timewindow", String(usesTimeWindow)),
            ("uses_cooldown", String(usesCooldown)),
            ("uses_weekday", String(usesWeekday))
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

    /// 최빈 규칙(그룹당 1표의 규칙 표기 — rawValue 또는 "weekday"). 비어 있거나 동률이면 "none".
    static func primaryRuleKind(of descriptors: [String]) -> String {
        let meaningful = descriptors.filter { $0 != "none" }
        guard !meaningful.isEmpty else { return "none" }
        let counts = Dictionary(grouping: meaningful, by: { $0 }).mapValues { $0.count }
        let maxCount = counts.values.max() ?? 0
        let leaders = counts.filter { $0.value == maxCount }
        guard leaders.count == 1, let kind = leaders.keys.first else { return "none" }
        return kind
    }
}
