import Foundation

struct RuleAnalyticsPayload {
    let ruleKind: String
    let ruleConfigBucket: String
    let selectionCountBucket: String
    let dailyLimitBucket: String?
    let timeWindowCountBucket: String?
    let timeWindowTotalBucket: String?
    let cooldownUsageBucket: String?
    let cooldownDurationBucket: String?
    /// 요일별 모드의 제한 요일 수(1~7) 버킷. 요일별 세부 파라미터는 요일 수가 곧 구성 복잡도라
    /// 이 버킷 하나로만 관찰한다(익명화 원칙 — 원값·요일 조합 비전송).
    let weekdayRestrictedDaysBucket: String?

    init(group: ScreenTimeGroup) {
        selectionCountBucket = Self.selectionCountBucket(group.selectionCount)

        // 요일별 모드는 base ruleKind(폴백용)가 아니라 "weekday"로 관찰한다.
        if let rules = group.weekdayRules {
            ruleKind = "weekday"
            let bucket = Self.weekdayRestrictedDaysBucket(
                rules.filter { $0.kind != .unrestricted }.count
            )
            ruleConfigBucket = bucket
            weekdayRestrictedDaysBucket = bucket
            dailyLimitBucket = nil
            timeWindowCountBucket = nil
            timeWindowTotalBucket = nil
            cooldownUsageBucket = nil
            cooldownDurationBucket = nil
            return
        }

        ruleKind = group.ruleKind?.rawValue ?? "unknown"
        weekdayRestrictedDaysBucket = nil

        switch group.ruleKind {
        case .dailyLimit:
            let bucket = Self.dailyLimitBucket(group.dailyLimitMinutes)
            ruleConfigBucket = bucket
            dailyLimitBucket = bucket
            timeWindowCountBucket = nil
            timeWindowTotalBucket = nil
            cooldownUsageBucket = nil
            cooldownDurationBucket = nil
        case .timeWindows:
            let countBucket = Self.timeWindowCountBucket(group.timeWindows.count)
            let totalBucket = Self.timeWindowTotalBucket(group.timeWindows.reduce(0) { $0 + $1.durationMinutes })
            ruleConfigBucket = "\(countBucket)_\(totalBucket)"
            dailyLimitBucket = nil
            timeWindowCountBucket = countBucket
            timeWindowTotalBucket = totalBucket
            cooldownUsageBucket = nil
            cooldownDurationBucket = nil
        case .cooldown:
            let usageBucket = Self.cooldownUsageBucket(group.cooldownUsageMinutes)
            let durationBucket = Self.cooldownDurationBucket(group.cooldownDurationMinutes)
            ruleConfigBucket = "\(usageBucket)_\(durationBucket)"
            dailyLimitBucket = nil
            timeWindowCountBucket = nil
            timeWindowTotalBucket = nil
            cooldownUsageBucket = usageBucket
            cooldownDurationBucket = durationBucket
        case .none:
            ruleConfigBucket = "unknown"
            dailyLimitBucket = nil
            timeWindowCountBucket = nil
            timeWindowTotalBucket = nil
            cooldownUsageBucket = nil
            cooldownDurationBucket = nil
        }
    }

    var parameters: [String: Any] {
        var result: [String: Any] = [
            "rule_kind": ruleKind,
            "rule_config_bucket": ruleConfigBucket,
            "selection_count_bucket": selectionCountBucket
        ]

        if let dailyLimitBucket {
            result["daily_limit_bucket"] = dailyLimitBucket
        }
        if let timeWindowCountBucket {
            result["time_window_count_bucket"] = timeWindowCountBucket
        }
        if let timeWindowTotalBucket {
            result["time_window_total_bucket"] = timeWindowTotalBucket
        }
        if let cooldownUsageBucket {
            result["cooldown_usage_bucket"] = cooldownUsageBucket
        }
        if let cooldownDurationBucket {
            result["cooldown_duration_bucket"] = cooldownDurationBucket
        }
        if let weekdayRestrictedDaysBucket {
            result["weekday_restricted_days"] = weekdayRestrictedDaysBucket
        }

        return result
    }

    /// `rule_changed` 이벤트의 누적 사용량 버킷. 다른 버킷과 동일한 익명화 원칙(원값 비전송).
    static func usedBucket(_ minutes: Int) -> String {
        switch minutes {
        case ...0: return "used_0m"
        case 1...15: return "used_1_15m"
        case 16...30: return "used_16_30m"
        case 31...60: return "used_31_60m"
        case 61...120: return "used_61_120m"
        default: return "used_121m_plus"
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

    /// 제한 요일 수(전부 제한 없음은 정책이 거부하므로 실사용 1~7). 방어적으로 0~7로 clamp.
    static func weekdayRestrictedDaysBucket(_ count: Int) -> String {
        "days_\(min(max(count, 0), 7))"
    }
}
