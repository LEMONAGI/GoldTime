import Foundation

/// Firebase Analytics user property로 심을 코호트 축. 기존 이벤트(shield_lock_started, shield_extend_completed 등)를
/// 사용자 세그먼트별로 쪼개 보기 위한 데이터다.
///
/// - 개인정보 없이 **버킷/플래그**로만 구성한다(`RuleAnalyticsPayload`와 동일한 익명화 원칙).
/// - 기준 그룹은 `isApplied == true` 그룹 — `group_snapshot`의 적용 그룹 수와
///   동일 기준이라 대시보드 간 일관성이 유지된다.
/// - 규칙 조합은 top-level 그룹 단위로 센다. 요일별 그룹 안의 개별 요일 규칙을 별도 그룹으로
///   부풀리지 않아, 사용자가 실제로 만든 그룹 조합을 그대로 관찰할 수 있다.
/// - Firebase 제약: property 이름 ≤24자, 값 ≤36자(아래 이름/값 모두 만족).
struct UserCohortProperties {
    /// 적용된 그룹 중 최빈 규칙(그룹당 1표 — 요일별 그룹은 "weekday"). 동률·없음은 "none".
    let primaryRuleKind: String
    let usesDaily: Bool
    let usesTimeWindow: Bool
    let usesCooldown: Bool
    /// 요일별 규칙을 쓰는 적용 그룹이 하나라도 있는지.
    let usesWeekday: Bool
    /// 적용 그룹의 top-level 규칙 조합. 예: `wd1_dl1_tw0_cd1`.
    let activeRuleProfile: String
    /// 활성 연장 불가 기간이 적용된 그룹의 top-level 규칙 조합. 없으면 `wd0_dl0_tw0_cd0`.
    let strictRuleProfile: String

    init(groups: [ScreenTimeGroup], now: Date = Date()) {
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
        // 최빈 규칙은 그룹당 1표 유지 — 요일별 그룹이 요일 수만큼 표를 갖게 하면 분포가 왜곡된다.
        primaryRuleKind = Self.primaryRuleKind(
            of: applied.map { $0.usesWeekdayRules ? "weekday" : ($0.ruleKind?.rawValue ?? "none") }
        )
        activeRuleProfile = RuleGroupProfile(groups: applied).encoded
        strictRuleProfile = RuleGroupProfile(
            groups: applied.filter { $0.isStrictLockActive(at: now) }
        ).encoded
    }

    /// `analyticsRepository.setUserProperty(value, for: name)`에 그대로 넘길 (이름, 값) 목록.
    var entries: [(name: String, value: String?)] {
        [
            ("primary_rule_kind", primaryRuleKind),
            ("uses_daily", String(usesDaily)),
            ("uses_timewindow", String(usesTimeWindow)),
            ("uses_cooldown", String(usesCooldown)),
            ("uses_weekday", String(usesWeekday)),
            ("active_rule_profile", activeRuleProfile),
            ("strict_rule_profile", strictRuleProfile)
        ]
    }
}

/// Firebase user property value의 compact 표현. GoldTime 그룹은 최대 5개라 각 자릿수는 0...5이고,
/// 식별자·이름·선택 앱 없이 "어떤 top-level 잠금 그룹을 몇 개 쓰는가"만 남긴다.
private struct RuleGroupProfile {
    private var weekday = 0
    private var daily = 0
    private var timeWindow = 0
    private var cooldown = 0

    init(groups: [ScreenTimeGroup]) {
        for group in groups {
            if group.usesWeekdayRules {
                weekday += 1
                continue
            }

            switch group.ruleKind {
            case .dailyLimit:
                daily += 1
            case .timeWindows:
                timeWindow += 1
            case .cooldown:
                cooldown += 1
            case .none:
                // 적용된 그룹은 정책상 ruleKind가 있어야 하지만, 손상/미래 데이터는 profile에서
                // 제외한다. 전체 적용 그룹 수는 `group_snapshot`이 별도로 보존한다.
                continue
            }
        }
    }

    var encoded: String {
        "wd\(weekday)_dl\(daily)_tw\(timeWindow)_cd\(cooldown)"
    }
}

private extension UserCohortProperties {
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
