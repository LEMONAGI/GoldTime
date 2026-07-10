//
//  GoldTimeFormatters.swift
//  GoldTime
//

import Foundation

func goldTimeDurationText(seconds: Int) -> String {
    let minutes = Int((Double(max(0, seconds)) / 60.0).rounded(.up))
    if minutes < 60 {
        return String(localized: "common.minutes \(minutes)")
    }

    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    if remainingMinutes == 0 {
        return String(localized: "common.hours \(hours)")
    }
    return String(localized: "common.hourMinute \(hours) \(remainingMinutes)")
}

/// 자정 기준 분(0...1439)을 "HH:mm" 24시간 표기로 변환. 시간대 차단 규칙 표시에 사용.
func goldTimeClockText(minuteOfDay minute: Int) -> String {
    let clamped = max(0, min(minute, 24 * 60 - 1))
    return String(format: "%02d:%02d", clamped / 60, clamped % 60)
}

/// Date의 시:분을 "HH:mm" 24시간 표기로 변환. 쿨다운 종료 시각 표시에 사용.
func goldTimeClockText(date: Date, calendar: Calendar = .current) -> String {
    let components = calendar.dateComponents([.hour, .minute], from: date)
    return goldTimeClockText(minuteOfDay: (components.hour ?? 0) * 60 + (components.minute ?? 0))
}

/// DayRule 한 줄 요약(규칙 종류 포함 — "일일 한도 · 30분"). 값만 표기하면 무슨 규칙인지
/// 알 수 없다는 피드백에 따라 종류를 앞에 붙인다. 요일 묶음 행과 홈 카드 '오늘' 부제가 함께 쓴다.
func goldTimeDayRuleSummary(_ rule: DayRule) -> String {
    switch rule.kind {
    case .unrestricted:
        return String(localized: "rule.weekday.unrestricted")
    case .dailyLimit:
        return String(localized: "rule.weekday.summary.dailyLimit \(goldTimeDurationText(seconds: rule.dailyLimitMinutes * 60))")
    case .timeWindows:
        let sorted = rule.timeWindows.sorted { $0.startMinuteOfDay < $1.startMinuteOfDay }
        guard !sorted.isEmpty else { return String(localized: "rule.timeWindows.addPrompt") }
        let list = sorted
            .map { "\(goldTimeClockText(minuteOfDay: $0.startMinuteOfDay))–\(goldTimeClockText(minuteOfDay: $0.endMinuteOfDay))" }
            .joined(separator: ", ")
        return String(localized: "rule.weekday.summary.timeWindows \(list)")
    case .cooldown:
        let usage = goldTimeDurationText(seconds: rule.cooldownUsageMinutes * 60)
        let rest = goldTimeDurationText(seconds: rule.cooldownDurationMinutes * 60)
        return String(localized: "rule.weekday.summary.cooldown \(usage) \(rest)")
    }
}
