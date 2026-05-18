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
