//
//  TimeWindowPolicy.swift
//  GoldTime
//
//  시간대별 차단 규칙의 검증과 잠금 판정을 Apple framework 호출부 밖에서 다루는 순수 정책.
//

import Foundation

enum TimeWindowPolicy {
    static let maxWindowCount = 3
    /// DeviceActivitySchedule이 15분 미만 interval 등록을 거부하므로 사전에 막는다.
    static let minWindowMinutes = 15
    static let minutesPerDay = 24 * 60

    enum InvalidReason: Equatable {
        case empty
        case tooMany
        case outOfRange
        case crossesMidnight
        case tooShort
        case overlapping

        var userMessage: String {
            switch self {
            case .empty:
                return "차단 시간대를 1개 이상 추가해 주세요."
            case .tooMany:
                return "차단 시간대는 \(TimeWindowPolicy.maxWindowCount)개까지예요."
            case .outOfRange:
                return "시간대 설정이 올바르지 않아요."
            case .crossesMidnight:
                return "종료 시각은 시작 시각보다 늦어야 해요. 자정을 넘는 시간대는 두 개로 나눠 주세요."
            case .tooShort:
                return "차단 시간대는 \(TimeWindowPolicy.minWindowMinutes)분 이상이어야 해요."
            case .overlapping:
                return "겹치는 시간대가 있어요. 시간대를 조정해 주세요."
            }
        }
    }

    static func firstInvalidReason(for windows: [TimeWindow]) -> InvalidReason? {
        if windows.isEmpty {
            return .empty
        }

        if windows.count > maxWindowCount {
            return .tooMany
        }

        for window in windows {
            if window.startMinuteOfDay < 0 || window.endMinuteOfDay >= minutesPerDay {
                return .outOfRange
            }
            if window.startMinuteOfDay >= window.endMinuteOfDay {
                return .crossesMidnight
            }
            if window.durationMinutes < minWindowMinutes {
                return .tooShort
            }
        }

        let sorted = windows.sorted { $0.startMinuteOfDay < $1.startMinuteOfDay }
        for (current, next) in zip(sorted, sorted.dropFirst()) where next.startMinuteOfDay < current.endMinuteOfDay {
            return .overlapping
        }

        return nil
    }

    static func isInsideAnyWindow(minuteOfDay minute: Int, windows: [TimeWindow]) -> Bool {
        windows.contains { $0.contains(minuteOfDay: minute) }
    }

    /// 자정 기준 경과 분(0...1439). Presentation에서 SharedStore를 직접 참조하지 않도록
    /// SharedStore.minuteOfDay와 같은 계산을 Domain에도 둔다.
    static func minuteOfDay(for date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// 현재 시각이 속한 시간대의 종료 분. 잠금 안내("HH:mm까지 잠김")에 사용.
    static func activeWindowEnd(minuteOfDay minute: Int, windows: [TimeWindow]) -> Int? {
        windows.first { $0.contains(minuteOfDay: minute) }?.endMinuteOfDay
    }
}
