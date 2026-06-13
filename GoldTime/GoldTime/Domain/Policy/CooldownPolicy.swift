//
//  CooldownPolicy.swift
//  GoldTime
//
//  쿨다운 모드(사용 예산 + 강제 휴식) 검증을 Apple framework 호출부 밖에서 다루는 순수 정책.
//

import Foundation

enum CooldownPolicy {
    static let minUsageMinutes = 1
    static let maxUsageMinutes = 480     // 8시간
    static let minCooldownMinutes = 30
    static let maxCooldownMinutes = 1440 // 24시간

    enum InvalidReason: Equatable {
        case usageOutOfRange
        case cooldownOutOfRange

        var userMessage: String {
            switch self {
            case .usageOutOfRange:
                return "사용 시간은 1분 이상 8시간 이하로 정해 주세요."
            case .cooldownOutOfRange:
                return "휴식 간격은 30분 이상 24시간 이하로 정해 주세요."
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
