import Foundation

/// 앱 활성화 시 적용 그룹 하나를 GA4 이벤트 하나로 표현하는 현재 설정 스냅샷.
///
/// `weekday`와 `strict_lock`을 실제 집행 규칙과 같은 축에 놓지 않는다.
/// - 이벤트 이름: 균일 규칙 종류 또는 요일별 설정 방식
/// - `weekday_*_days`: 요일별 그룹 내부의 실제 집행 규칙별 요일 수
/// - `strict_lock_active`: 규칙과 독립적인 연장 불가 상태
struct RuleGroupSnapshotAnalytics {
    let eventName: String
    let parameters: [String: Any]
    let ruleMode: String
    let selectionCountBucket: String

    init?(group: ScreenTimeGroup, now: Date = Date()) {
        guard group.isApplied else { return nil }

        let rulePayload = RuleAnalyticsPayload(group: group)
        selectionCountBucket = rulePayload.selectionCountBucket
        var parameters: [String: Any] = [
            "selection_count_bucket": selectionCountBucket,
            "strict_lock_active": String(group.isStrictLockActive(at: now))
        ]

        if let rules = group.weekdayRules {
            eventName = "rule_weekday_snapshot"
            ruleMode = "weekday"
            parameters["rule_mode"] = ruleMode
            let dailyDays = rules.filter { $0.kind == .dailyLimit }.count
            let timeWindowDays = rules.filter { $0.kind == .timeWindows }.count
            let cooldownDays = rules.filter { $0.kind == .cooldown }.count
            let unrestrictedDays = rules.filter { $0.kind == .unrestricted }.count
            parameters["weekday_uses_daily"] = String(dailyDays > 0)
            parameters["weekday_uses_time_window"] = String(timeWindowDays > 0)
            parameters["weekday_uses_cooldown"] = String(cooldownDays > 0)
            parameters["weekday_daily_days"] = dailyDays
            parameters["weekday_time_window_days"] = timeWindowDays
            parameters["weekday_cooldown_days"] = cooldownDays
            parameters["weekday_unrestricted_days"] = unrestrictedDays
            self.parameters = parameters
            return
        }

        switch group.ruleKind {
        case .dailyLimit:
            eventName = "rule_uniform_daily"
            ruleMode = "uniform_daily"
            parameters["rule_mode"] = ruleMode
            parameters["uniform_daily_limit_bucket"] = rulePayload.dailyLimitBucket
        case .timeWindows:
            eventName = "rule_uniform_time_window"
            ruleMode = "uniform_time_window"
            parameters["rule_mode"] = ruleMode
            parameters["uniform_time_window_count_bucket"] = rulePayload.timeWindowCountBucket
            parameters["uniform_time_window_total_bucket"] = rulePayload.timeWindowTotalBucket
        case .cooldown:
            eventName = "rule_uniform_cooldown"
            ruleMode = "uniform_cooldown"
            parameters["rule_mode"] = ruleMode
            parameters["uniform_cooldown_usage_bucket"] = rulePayload.cooldownUsageBucket
            parameters["uniform_cooldown_duration_bucket"] = rulePayload.cooldownDurationBucket
        case .none:
            return nil
        }

        self.parameters = parameters
    }
}

/// 규칙 설정값을 익명 버킷으로 환산하는 계산기. **이벤트를 직접 만들지 않는다** —
/// 버킷 문자열만 계산해 `RuleGroupSnapshotAnalytics`(스냅샷 이벤트)와
/// `ShieldExtendAnalyticsPayload`에 공급한다.
///
/// 1.3.0에서 `parameters` 계산 속성과 `ruleKind`·`ruleConfigBucket`·`weekdayRestrictedDaysBucket`을
/// 제거했다: 구 계약(`group_applied`에 규칙 상세를 실어 보내던 방식)의 잔재로 **프로덕션 호출부가
/// 하나도 없는 죽은 코드**였고, 코드에 남은 구 파라미터 이름(`rule_kind`/`rule_config_bucket`/
/// `daily_limit_bucket`/`weekday_restricted_days`)이 "아직 전송된다"는 오해를 만들었다.
/// 규칙 상세는 이제 `uniform_*`·`weekday_*_days` 이름으로 스냅샷 이벤트에만 실린다.
/// 이벤트 파라미터를 여기서 다시 조립하지 말 것.
struct RuleAnalyticsPayload {
    let selectionCountBucket: String
    let dailyLimitBucket: String?
    let timeWindowCountBucket: String?
    let timeWindowTotalBucket: String?
    let cooldownUsageBucket: String?
    let cooldownDurationBucket: String?

    init(group: ScreenTimeGroup) {
        selectionCountBucket = Self.selectionCountBucket(group.selectionCount)

        // 요일별 모드는 base 규칙(폴백용)의 버킷을 내지 않는다 — 요일별 구성은
        // `RuleGroupSnapshotAnalytics`가 `weekday_*_days`로 따로 관찰한다.
        if group.weekdayRules != nil {
            dailyLimitBucket = nil
            timeWindowCountBucket = nil
            timeWindowTotalBucket = nil
            cooldownUsageBucket = nil
            cooldownDurationBucket = nil
            return
        }

        switch group.ruleKind {
        case .dailyLimit:
            dailyLimitBucket = Self.dailyLimitBucket(group.dailyLimitMinutes)
            timeWindowCountBucket = nil
            timeWindowTotalBucket = nil
            cooldownUsageBucket = nil
            cooldownDurationBucket = nil
        case .timeWindows:
            dailyLimitBucket = nil
            timeWindowCountBucket = Self.timeWindowCountBucket(group.timeWindows.count)
            timeWindowTotalBucket = Self.timeWindowTotalBucket(
                group.timeWindows.reduce(0) { $0 + $1.durationMinutes }
            )
            cooldownUsageBucket = nil
            cooldownDurationBucket = nil
        case .cooldown:
            dailyLimitBucket = nil
            timeWindowCountBucket = nil
            timeWindowTotalBucket = nil
            cooldownUsageBucket = Self.cooldownUsageBucket(group.cooldownUsageMinutes)
            cooldownDurationBucket = Self.cooldownDurationBucket(group.cooldownDurationMinutes)
        case .none:
            dailyLimitBucket = nil
            timeWindowCountBucket = nil
            timeWindowTotalBucket = nil
            cooldownUsageBucket = nil
            cooldownDurationBucket = nil
        }
    }
}

/// Shield 연장 성공 시 설정 방식과 오늘 실제 집행 규칙을 함께 보존한다.
///
/// 요일별 그룹은 `rule_mode=weekday`인 동시에 오늘 투영된 규칙을
/// `enforcement_rule`로 보내야 어느 설정에서 무엇 때문에 연장했는지 구분할 수 있다.
struct ShieldExtendAnalyticsPayload {
    let parameters: [String: Any]

    init(group: ScreenTimeGroup, now: Date = Date()) {
        var parameters = RuleGroupSnapshotAnalytics(group: group, now: now)?.parameters ?? [
            "rule_mode": Self.ruleMode(for: group),
            "selection_count_bucket": RuleAnalyticsPayload(group: group).selectionCountBucket
        ]
        parameters["enforcement_rule"] = Self.enforcementRule(for: group.resolved(on: now))
        self.parameters = parameters
    }

    private static func ruleMode(for group: ScreenTimeGroup) -> String {
        if group.weekdayRules != nil { return "weekday" }
        switch group.ruleKind {
        case .dailyLimit: return "uniform_daily"
        case .timeWindows: return "uniform_time_window"
        case .cooldown: return "uniform_cooldown"
        case .none: return "unknown"
        }
    }

    private static func enforcementRule(for group: ScreenTimeGroup) -> String {
        switch group.ruleKind {
        case .dailyLimit: return "daily"
        case .timeWindows: return "time_window"
        case .cooldown: return "cooldown"
        case .none: return "unknown"
        }
    }
}

private extension RuleAnalyticsPayload {
    static func selectionCountBucket(_ count: Int) -> String {
        switch count {
        case 0: return "selection_0"
        case 1: return "selection_1"
        case 2...3: return "selection_2_3"
        case 4...6: return "selection_4_6"
        case 7...9: return "selection_7_9"
        default: return "selection_10_plus"
        }
    }

    static func dailyLimitBucket(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "daily_0m"
        case 1...15: return "daily_1_15m"
        case 16...30: return "daily_16_30m"
        case 31...60: return "daily_31_60m"
        case 61...120: return "daily_61_120m"
        case 121...240: return "daily_121_240m"
        default: return "daily_241m_plus"
        }
    }

    static func timeWindowCountBucket(_ count: Int) -> String {
        switch count {
        case 0: return "windows_0"
        case 1: return "windows_1"
        case 2: return "windows_2"
        case 3: return "windows_3"
        default: return "windows_4_plus"
        }
    }

    static func timeWindowTotalBucket(_ minutes: Int) -> String {
        switch minutes {
        case 0...60: return "total_15_60m"
        case 61...180: return "total_61_180m"
        case 181...360: return "total_181_360m"
        default: return "total_361m_plus"
        }
    }

    static func cooldownUsageBucket(_ minutes: Int) -> String {
        switch minutes {
        case 0...15: return "usage_5_15m"
        case 16...30: return "usage_16_30m"
        case 31...60: return "usage_31_60m"
        default: return "usage_61_120m"
        }
    }

    static func cooldownDurationBucket(_ minutes: Int) -> String {
        switch minutes {
        case 0...60: return "rest_30_60m"
        case 61...120: return "rest_61_120m"
        case 121...240: return "rest_121_240m"
        default: return "rest_241_360m"
        }
    }

}
