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
                return String(localized: "timeWindow.error.empty")
            case .tooMany:
                return String(localized: "timeWindow.error.tooMany \(TimeWindowPolicy.maxWindowCount)")
            case .outOfRange:
                return String(localized: "timeWindow.error.outOfRange")
            case .crossesMidnight:
                return String(localized: "timeWindow.error.crossesMidnight")
            case .tooShort:
                return String(localized: "timeWindow.error.tooShort \(TimeWindowPolicy.minWindowMinutes)")
            case .overlapping:
                return String(localized: "timeWindow.error.overlapping")
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
            if window.startMinuteOfDay > window.endMinuteOfDay {
                return .crossesMidnight
            }
            if window.durationMinutes < minWindowMinutes {
                return .tooShort
            }
        }

        // end가 inclusive(차단되는 마지막 분)이므로, 다음 시작이 현재 종료와 같거나 빠르면 겹침.
        // 예) 12:00–13:00 + 13:00–14:00 → 13:00을 둘 다 차단하므로 거부. 연속 차단은 12:00–12:59 + 13:00–14:00.
        let sorted = windows.sorted { $0.startMinuteOfDay < $1.startMinuteOfDay }
        for (current, next) in zip(sorted, sorted.dropFirst()) where next.startMinuteOfDay <= current.endMinuteOfDay {
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

    /// 지금 속한 시간대부터 (종료 분 + 1 == 다음 시작)으로 인접하게 이어지는 마지막 시간대의
    /// inclusive 종료 분. 예: 21:00–21:59, 22:00–22:59가 붙어 있으면 22:59(1379) 반환.
    /// end가 inclusive이므로 인접 조건은 `window.start == end + 1`. 어디에도 안 속하면 nil.
    static func contiguousWindowEnd(minuteOfDay minute: Int, windows: [TimeWindow]) -> Int? {
        let sorted = windows.sorted { $0.startMinuteOfDay < $1.startMinuteOfDay }
        guard var end = sorted.first(where: { $0.contains(minuteOfDay: minute) })?.endMinuteOfDay else {
            return nil
        }
        for window in sorted where window.startMinuteOfDay == end + 1 {
            end = window.endMinuteOfDay
        }
        return end
    }

    /// 현재 분 이후 가장 가까운 시간대 시작 분. 오늘 남은 게 없으면 가장 이른 시작(다음날)으로 wrap.
    /// "HH:mm까지 사용 가능" 안내에 사용. 시간대가 없으면 nil.
    static func nextWindowStart(minuteOfDay minute: Int, windows: [TimeWindow]) -> Int? {
        let starts = windows.map(\.startMinuteOfDay).sorted()
        guard !starts.isEmpty else { return nil }
        return starts.first { $0 > minute } ?? starts.first
    }
}
