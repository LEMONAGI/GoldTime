//
//  WeekdayRulePolicy.swift
//  GoldTime
//
//  요일별 제한 규칙(DayRule 7개)의 검증과 요일 인덱스 계산을 Apple framework 호출부 밖에서
//  다루는 순수 정책. 개별 요일의 유효성은 기존 정책 3종(일일/시간대/쿨다운)에 위임한다.
//

import Foundation

enum WeekdayRulePolicy {
    /// 특정 요일의 규칙이 무효한 이유. 하위 정책의 사유를 그대로 감싸거나 일일 한도 자체 검증을 담는다.
    enum DayInvalidReason: Equatable {
        case dailyLimit
        case timeWindow(TimeWindowPolicy.InvalidReason)
        case cooldown(CooldownPolicy.InvalidReason)

        var userMessage: String {
            switch self {
            case .dailyLimit:
                return String(localized: "weekdayRule.error.dailyLimit")
            case .timeWindow(let reason):
                return reason.userMessage
            case .cooldown(let reason):
                return reason.userMessage
            }
        }
    }

    enum InvalidReason: Equatable {
        /// 방어용: 요일 규칙이 정확히 7개가 아니다.
        case wrongDayCount
        /// 7일 전부 제한 없음 — 적용할 규칙이 없어 무효.
        case allUnrestricted
        /// 특정 요일(weekdayIndex, 0=일 … 6=토)의 규칙이 무효.
        case dayInvalid(weekdayIndex: Int, DayInvalidReason)

        var userMessage: String {
            switch self {
            case .wrongDayCount:
                return String(localized: "weekdayRule.error.wrongDayCount")
            case .allUnrestricted:
                return String(localized: "weekdayRule.error.allUnrestricted")
            case .dayInvalid(let weekdayIndex, let reason):
                let dayName = Calendar.current.weekdaySymbols[weekdayIndex]
                return String(localized: "weekdayRule.error.dayInvalid \(dayName) \(reason.userMessage)")
            }
        }
    }

    /// 날짜의 요일 인덱스(0=일 … 6=토). Calendar.weekday는 firstWeekday(주 시작 요일) 설정과
    /// 무관하게 항상 1=일요일로 고정이라, weekStartDay 설정이 무엇이든 인덱스가 안정적이다.
    static func weekdayIndex(for date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: date) - 1
    }

    /// 표시 순서용 요일 인덱스 배열. weekStartDay(1=일 … 7=토, SharedStore.weekStartDay와 동일 의미)가
    /// 첫 요소가 되도록 [0...6]을 회전한다. 범위 밖 값은 월요일 시작(2)으로 폴백한다
    /// (SharedStore.weekStartDay getter의 기본값 2와 동일하게 유지).
    static func displayOrderedIndices(weekStartDay: Int) -> [Int] {
        let start = (1...7).contains(weekStartDay) ? weekStartDay - 1 : 1
        return (0..<7).map { (start + $0) % 7 }
    }

    /// 첫 번째 무효 이유를 반환한다. 유효하면 nil.
    /// 개별 요일 검증은 그룹 규칙과 동일한 정책(TimeWindowPolicy/CooldownPolicy·일일 한도 조건)에 위임한다.
    static func firstInvalidReason(for rules: [DayRule]) -> InvalidReason? {
        guard rules.count == 7 else {
            return .wrongDayCount
        }

        if rules.allSatisfy({ $0.kind == .unrestricted }) {
            return .allUnrestricted
        }

        for (index, rule) in rules.enumerated() {
            switch rule.kind {
            case .unrestricted:
                continue
            case .dailyLimit:
                // ScreenTimeGroupPolicy.ruleInvalidReason의 .dailyLimit 검증과 동일 조건.
                if rule.dailyLimitMinutes < 0 {
                    return .dayInvalid(weekdayIndex: index, .dailyLimit)
                }
            case .timeWindows:
                // 그룹 규칙과 동일하게 빈 배열도 TimeWindowPolicy가 .empty로 잡는다.
                if let reason = TimeWindowPolicy.firstInvalidReason(for: rule.timeWindows) {
                    return .dayInvalid(weekdayIndex: index, .timeWindow(reason))
                }
            case .cooldown:
                if let reason = CooldownPolicy.firstInvalidReason(
                    usageMinutes: rule.cooldownUsageMinutes,
                    cooldownMinutes: rule.cooldownDurationMinutes
                ) {
                    return .dayInvalid(weekdayIndex: index, .cooldown(reason))
                }
            }
        }

        return nil
    }
}
