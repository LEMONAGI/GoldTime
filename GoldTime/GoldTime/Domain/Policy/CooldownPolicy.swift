//
//  CooldownPolicy.swift
//  GoldTime
//
//  쿨다운 모드(사용 예산 + 강제 휴식) 검증을 Apple framework 호출부 밖에서 다루는 순수 정책.
//

import Foundation

enum CooldownPolicy {
    static let minUsageMinutes = 5
    static let maxUsageMinutes = 120     // 2시간
    static let minCooldownMinutes = 30
    static let maxCooldownMinutes = 360  // 6시간

    enum InvalidReason: Equatable {
        case usageOutOfRange
        case cooldownOutOfRange

        var userMessage: String {
            switch self {
            case .usageOutOfRange:
                return String(localized: "cooldown.error.usageOutOfRange")
            case .cooldownOutOfRange:
                return String(localized: "cooldown.error.cooldownOutOfRange")
            }
        }
    }

    /// 첫 번째 무효 이유를 반환한다. 유효하면 nil.
    static func firstInvalidReason(usageMinutes: Int, cooldownMinutes: Int) -> InvalidReason? {
        if usageMinutes < minUsageMinutes || usageMinutes > maxUsageMinutes {
            return .usageOutOfRange
        }
        if cooldownMinutes < minCooldownMinutes || cooldownMinutes > maxCooldownMinutes {
            return .cooldownOutOfRange
        }
        return nil
    }
}
