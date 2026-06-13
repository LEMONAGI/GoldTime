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

    /// 사용 예산 모니터 등록. cooldownUsageMinutes분 사용 시 cdtick 이벤트가 1회 발화한다.
    /// 한 번에 단일 이벤트만 등록하므로(no relay) 재발화 누적 버그에 면역.
    nonisolated static func startUsageMonitoring(
        center: DeviceActivityCenter,
        group: SharedStore.ScreenTimeGroup,
        generation: Int,
        now: Date = Date()
    ) throws {
        let minutes = group.cooldownUsageMinutes
        guard minutes > 0 else { return }

        let event = DeviceActivityEvent(
            applications: group.selection.applicationTokens,
            categories: [],
            webDomains: group.selection.webDomainTokens,
            threshold: DateComponents(minute: minutes)
        )
        try center.startMonitoring(
            .cooldownUsage(for: group.id, generation: generation),
            during: usageSchedule(now: now),
            events: [.cooldownTick(for: group.id, minute: minutes): event]
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
