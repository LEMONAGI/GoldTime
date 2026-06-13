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

    /// 사용 예산 모니터 등록. 누적 사용 분이 각 threshold에 닿을 때마다 cdtick이 1회씩 발화한다.
    /// 진행바(남은 시간)를 위해 최대 10개 threshold를 한 번에 등록(no relay)하며, 마지막
    /// threshold(=cooldownUsageMinutes)에서 잠금이 트리거된다. 사이클마다 새 window라 baseline 불필요.
    nonisolated static func startUsageMonitoring(
        center: DeviceActivityCenter,
        group: SharedStore.ScreenTimeGroup,
        generation: Int,
        now: Date = Date()
    ) throws {
        let budget = group.cooldownUsageMinutes
        guard budget > 0 else { return }
        let thresholds = usageThresholds(forBudget: budget)
        guard !thresholds.isEmpty else { return }

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
    /// 자정을 넘을 수 있으므로 절대 시각(year~second)으로 등록한다(override 패턴과 동일).
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
