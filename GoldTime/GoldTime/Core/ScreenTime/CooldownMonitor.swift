//
//  CooldownMonitor.swift
//  GoldTime
//
//  쿨다운 모드의 DeviceActivity 이름 규약과 등록을 메인 앱과 extension이 공유한다.
//  (extension은 ScreenTimeManager를 포함하지 않으므로, 휴식 종료 후 사용 예산 모니터를
//  재등록하려면 등록 로직을 공유해야 한다. 그래서 이 파일은 두 타겟 모두에 포함된다.)
//

import DeviceActivity
import FamilyControls
import Foundation

extension DeviceActivityName {
    /// 사용 예산 추적 활동. `cooldownUsage.<gid>.<gen>` 형식. generation으로 재등록 시
    /// DeviceActivity의 schedule-interval 누적 카운터를 분리한다(daily generation 트릭과 동일).
    nonisolated static func cooldownUsage(for groupID: UUID, generation: Int) -> Self {
        Self("cooldownUsage.\(groupID.uuidString).\(generation)")
    }

    /// `cooldownUsage.<gid>.<gen>`에서 groupID 추출.
    var cooldownUsageGroupID: UUID? {
        let prefix = "cooldownUsage."
        guard rawValue.hasPrefix(prefix) else { return nil }
        let body = String(rawValue.dropFirst(prefix.count))
        let first = body.split(separator: ".").first.map(String.init) ?? body
        return UUID(uuidString: first)
    }

    /// 휴식 타이머 활동. `cooldownTimer.<gid>` 형식(접두사가 cooldownUsage와 겹치지 않게 분리).
    /// 종료(intervalDidEnd) 시 재충전한다.
    nonisolated static func cooldownTimer(for groupID: UUID) -> Self {
        Self("cooldownTimer.\(groupID.uuidString)")
    }

    /// `cooldownTimer.<gid>`에서 groupID 추출.
    var cooldownTimerGroupID: UUID? {
        let prefix = "cooldownTimer."
        guard rawValue.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(rawValue.dropFirst(prefix.count)))
    }
}

extension DeviceActivityEvent.Name {
    /// 사용 예산 소진 이벤트. `cdtick.<gid>.<minute>` 형식. 등록 시점부터 누적 minute분 사용 시
    /// 한 번 발화한다(relay 없음 → iOS 26 즉시발화 regression에 면역).
    nonisolated static func cooldownTick(for groupID: UUID, minute: Int) -> Self {
        Self("cdtick.\(groupID.uuidString).\(minute)")
    }

    /// `cdtick.<gid>.<minute>`에서 (groupID, minute) 추출.
    var cooldownTickInfo: (groupID: UUID, minute: Int)? {
        let prefix = "cdtick."
        guard rawValue.hasPrefix(prefix) else { return nil }
        let parts = rawValue.dropFirst(prefix.count).split(separator: ".")
        guard parts.count == 2,
              let groupID = UUID(uuidString: String(parts[0])),
              let minute = Int(parts[1]) else { return nil }
        return (groupID, minute)
    }
}

/// 쿨다운 모드 DeviceActivity 등록 헬퍼. 메인 앱(ScreenTimeManager)과 extension이 공유.
enum CooldownMonitor {
    /// 사용 예산 측정 창: "지금"부터 오늘 23:59:59까지의 1회성 창(freshDailyWindow와 동일 형태).
    nonisolated static func usageSchedule(now: Date = Date(), calendar: Calendar = .current) -> DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.hour, .minute, .second], from: now),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: false
        )
    }

    /// 사용 예산(분)을 최대 maxEvents개 threshold로 나눈 목록. 예산이 maxEvents 이하면 1분 단위,
    /// 초과하면 균등 분배하되 마지막은 정확히 예산. (daily의 dailyThresholdMinutes와 동일 규칙)
    nonisolated static func usageThresholds(forBudget budget: Int, maxEvents: Int = 10) -> [Int] {
        guard budget > 0 else { return [] }
        if budget <= maxEvents {
            return Array(1...budget)
        }
        var set = Set<Int>()
        for i in 1...maxEvents {
            let m = Int((Double(budget) * Double(i) / Double(maxEvents)).rounded())
            if m >= 1 { set.insert(min(m, budget)) }
        }
        set.insert(budget)
        return set.sorted()
    }

    /// 이미 쓴 사용량을 제외한 남은 예산에 대한 상대 threshold 목록.
    /// 예: 30분 예산에서 5분 사용 후 재등록하면 마지막 threshold는 25분이다.
    nonisolated static func usageThresholds(
        forBudget budget: Int,
        baseline: Int,
        maxEvents: Int = 10
    ) -> [Int] {
        usageThresholds(forBudget: budget - max(0, baseline), maxEvents: maxEvents)
    }

    /// cooldownUsage tick의 상대 분을 사이클 전체 사용량으로 복원한다.
    nonisolated static func absoluteUsedMinutes(baseline: Int, tickMinute: Int) -> Int {
        max(0, baseline) + max(0, tickMinute)
    }

    /// 휴식 타이머 종료 콜백에서 실제로 재충전해야 하는지 판정한다(Apple framework 호출 없는 순수 판정).
    /// `cooldownEnd`가 없으면(이미 해제됐거나 자정 리셋) false, 종료 예정 시각이 아직 미래면(설정 변경
    /// 재동기화 등으로 타이머가 휴식 종료보다 일찍 멈춘 경우) false → 둘 다 현재 휴식을 보존해야 한다.
    nonisolated static func shouldRechargeOnTimerEnd(cooldownEnd: Date?, now: Date) -> Bool {
        guard let end = cooldownEnd else { return false }
        return end <= now
    }

    /// 휴식 종료 시각. 쿨다운은 매일 자정에 새로 시작하므로 휴식이 내일로 넘어가면 오늘 23:59:59로 자른다.
    nonisolated static func cooldownEnd(
        now: Date = Date(),
        durationMinutes: Int,
        calendar: Calendar = .current
    ) -> Date {
        let unclamped = now.addingTimeInterval(TimeInterval(max(0, durationMinutes) * 60))
        guard !calendar.isDate(unclamped, inSameDayAs: now) else {
            return unclamped
        }
        return calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? unclamped
    }

    /// 사용 예산 모니터 등록. 등록 시점까지의 누적 사용량을 baseline으로 저장하고, 남은 예산에
    /// 대한 상대 threshold를 건다. 진행바(남은 시간)를 위해 최대 10개 threshold를 한 번에 등록
    /// (no relay)하며, 마지막 threshold에서 `baseline + tick == cooldownUsageMinutes`가 되어 잠금된다.
    nonisolated static func startUsageMonitoring(
        center: DeviceActivityCenter,
        group: SharedStore.ScreenTimeGroup,
        generation: Int,
        now: Date = Date()
    ) throws {
        let budget = group.cooldownUsageMinutes
        guard budget > 0 else { return }
        let baseline = max(0, SharedStore.usedTimeByGroupID[group.id] ?? 0)
        let thresholds = usageThresholds(forBudget: budget, baseline: baseline)
        guard !thresholds.isEmpty else { return }
        SharedStore.cooldownBaselineByGroupID[group.id] = baseline

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for minute in thresholds {
            events[.cooldownTick(for: group.id, minute: minute)] = DeviceActivityEvent(
                applications: group.selection.applicationTokens,
                categories: [],
                webDomains: group.selection.webDomainTokens,
                threshold: DateComponents(minute: minute)
            )
        }
        try center.startMonitoring(
            .cooldownUsage(for: group.id, generation: generation),
            during: usageSchedule(now: now),
            events: events
        )
    }

    /// 휴식 타이머 등록. now ~ until 1회성 창(이벤트 없음). 종료 시 intervalDidEnd로 재충전한다.
    /// until은 `cooldownEnd`로 당일 23:59:59 안에 clamp한 값을 전달한다.
    nonisolated static func startCooldownTimer(
        center: DeviceActivityCenter,
        groupID: UUID,
        until: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws {
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: now),
            intervalEnd: calendar.dateComponents(components, from: until),
            repeats: false
        )
        try center.startMonitoring(
            .cooldownTimer(for: groupID),
            during: schedule,
            events: [:]
        )
    }
}
