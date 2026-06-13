//
//  GoldTimeFormatters.swift
//  GoldTime
//

import Foundation

func goldTimeDurationText(seconds: Int) -> String {
    let minutes = Int((Double(max(0, seconds)) / 60.0).rounded(.up))
    if minutes < 60 {
        return "\(minutes)분"
    }

    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    if remainingMinutes == 0 {
        return "\(hours)시간"
    }
    return "\(hours)시간 \(remainingMinutes)분"
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
