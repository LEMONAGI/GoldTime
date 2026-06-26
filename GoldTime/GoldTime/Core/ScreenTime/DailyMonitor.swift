//
//  DailyMonitor.swift
//  GoldTime
//
//  일일 한도 모드의 DeviceActivity 이름·스케줄·threshold 등록과, 모든 모드가 공유하는
//  자정 하트비트를 메인 앱과 extension이 함께 쓴다.
//  (extension은 ScreenTimeManager를 포함하지 않으므로, 자정 하트비트에서 daily 모니터를
//  재등록하려면 등록 로직을 공유해야 한다. 그래서 이 파일은 두 타겟 모두에 포함된다 —
//  CooldownMonitor와 동일한 이유.)
//
//  ⚠️ 여기 있는 DeviceActivityName/DeviceActivityEvent.Name 헬퍼는 공유 단일 출처다.
//  ScreenTimeManager나 DeviceActivityMonitorExtension에 같은 멤버를 다시 선언하면 두 타겟에서
//  중복 선언이 된다(daily/dailyGroup/dailyGroupID/dailyHeartbeat/tick/tickInfo).
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import os

extension DeviceActivityName {
    static let daily = Self("daily")

    /// 모든 모드 공통 자정 하트비트. `00:00 ~ 23:59:59, repeats:true`로 매일 자정 intervalDidStart가
    /// 발화해 일일 리셋 + daily/cooldown 모니터 재등록의 주 경로가 된다(date-less 측정창의 undocumented
    /// 재무장에 의존하지 않기 위함). 그룹당이 아니라 단일 activity.
    static let dailyHeartbeat = Self("dailyHeartbeat")

    /// `daily.<UUID>.<generation>` 형식. 재시작 시 generation을 +1 해서 시스템 카운터를 분리한다.
    nonisolated static func dailyGroup(for groupID: UUID, generation: Int) -> Self {
        Self("daily.\(groupID.uuidString).\(generation)")
    }

    /// 옛 형식(`daily.<UUID>`)과 새 형식(`daily.<UUID>.<gen>`) 모두 인식.
    /// `daily`(하트비트 아님) 및 `dailyHeartbeat`는 제외한다.
    var dailyGroupID: UUID? {
        let prefix = "daily."
        guard rawValue.hasPrefix(prefix), rawValue != "daily" else { return nil }
        let body = String(rawValue.dropFirst(prefix.count))
        let firstSegment = body.split(separator: ".").first.map(String.init) ?? body
        return UUID(uuidString: firstSegment)
    }
}

extension DeviceActivityEvent.Name {
    /// daily 한도 추적 1회성 이벤트. `tick.<gid>.<minute>` 형식으로 등록 시점부터 누적
    /// minute분 사용 시 한 번 발화한다 (relay 없음 → iOS 26 즉시발화 regression에 면역).
    nonisolated static func tick(for groupID: UUID, minute: Int) -> Self {
        Self("tick.\(groupID.uuidString).\(minute)")
    }

    /// `tick.<gid>.<minute>`에서 (groupID, minute) 추출.
    var tickInfo: (groupID: UUID, minute: Int)? {
        let prefix = "tick."
        guard rawValue.hasPrefix(prefix) else { return nil }
        let body = rawValue.dropFirst(prefix.count)
        let parts = body.split(separator: ".")
        guard parts.count == 2,
              let groupID = UUID(uuidString: String(parts[0])),
              let minute = Int(parts[1]) else { return nil }
        return (groupID, minute)
    }
}

extension SharedStore.ScreenTimeGroup {
    var policySnapshot: ScreenTimeGroupPolicy.GroupSnapshot<ApplicationToken> {
        ScreenTimeGroupPolicy.GroupSnapshot(
            id: id,
            name: displayName,
            appTokens: selection.applicationTokens,
            webDomainTokenCount: selection.webDomainTokens.count,
            hasNonAppTokens: hasNonAppTokens,
            dailyLimitMinutes: dailyLimitMinutes,
            ruleKind: ruleKind,
            timeWindows: timeWindows,
            isApplied: isApplied,
            cooldownUsageMinutes: cooldownUsageMinutes,
            cooldownDurationMinutes: cooldownDurationMinutes
        )
    }
}

extension Array where Element == SharedStore.ScreenTimeGroup {
    var policySnapshots: [ScreenTimeGroupPolicy.GroupSnapshot<ApplicationToken>] {
        map(\.policySnapshot)
    }
}

/// 일일 한도 DeviceActivity 등록 헬퍼 + 자정 하트비트. 메인 앱(ScreenTimeManager)과 extension이 공유.
enum DailyMonitor {
    /// 모든 모드 공통 자정 하트비트 스케줄. `00:00 ~ 23:59:59, repeats:true, events 없음`.
    /// 매일 자정 intervalDidStart가 발화하므로 일일 리셋·재무장의 신뢰 가능한 주 경로가 된다.
    nonisolated static var heartbeatSchedule: DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
    }

    /// "지금"부터 오늘 23:59:59까지의 1회성 창. intervalStart가 now라 그 이전 사용량(앱을
    /// 그룹에 추가하기 전 사용분)은 측정에서 제외된다. ⚠️ 반드시 date-less(`.hour,.minute,.second`)·
    /// `repeats:false`여야 한다 — `.day`(절대 날짜)를 넣으면 threshold가 즉시·배치 발화한다(회귀 204a691).
    nonisolated static func freshDailyWindow(now: Date = Date()) -> DeviceActivitySchedule {
        let calendar = Calendar.current
        return DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.hour, .minute, .second], from: now),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: false
        )
    }

    /// daily 한도(분)에 대한 1회성 threshold 목록. 한도가 maxEvents 이하면 1,2,…,limit
    /// (1분 단위), 초과하면 maxEvents개로 균등 분배하되 마지막은 정확히 limit.
    /// 이벤트를 한 번에 다 등록(no relay)하므로 iOS 26 즉시발화 regression에 면역.
    /// 한도가 maxEvents의 배수면 정확히 maxEvents개가 limit/maxEvents분 간격으로 균등 배치된다.
    nonisolated static func dailyThresholdMinutes(limit: Int, maxEvents: Int = 10) -> [Int] {
        guard limit > 0 else { return [] }
        if limit <= maxEvents {
            return Array(1...limit)
        }
        var set = Set<Int>()
        for i in 1...maxEvents {
            let m = Int((Double(limit) * Double(i) / Double(maxEvents)).rounded())
            if m >= 1 { set.insert(min(m, limit)) }
        }
        set.insert(limit)
        return set.sorted()
    }

    /// daily 한도 모니터 등록. baseline(등록 시점 usedTime)을 저장하고 남은 한도에 대한 상대
    /// threshold를 1회성 창(freshDailyWindow)으로 건다. remaining<=0이면 등록하지 않는다
    /// (호출부가 즉시 잠금 처리). 메인 앱(syncDailyMonitoring)과 extension(자정 하트비트) 공유.
    nonisolated static func startUsageMonitoring(
        center: DeviceActivityCenter,
        group: SharedStore.ScreenTimeGroup,
        generation: Int,
        now: Date = Date()
    ) throws {
        let baseline = SharedStore.usedTimeByGroupID[group.id] ?? 0
        let remaining = group.dailyLimitMinutes - baseline
        guard remaining > 0 else { return }

        SharedStore.dailyBaselineByGroupID[group.id] = baseline
        let thresholds = dailyThresholdMinutes(limit: remaining)
        guard !thresholds.isEmpty else { return }

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for minute in thresholds {
            events[.tick(for: group.id, minute: minute)] = DeviceActivityEvent(
                applications: group.selection.applicationTokens,
                categories: [],
                webDomains: group.selection.webDomainTokens,
                threshold: DateComponents(minute: minute)
            )
        }
        try center.startMonitoring(
            .dailyGroup(for: group.id, generation: generation),
            during: freshDailyWindow(now: now),
            events: events
        )
        GTLog.dailyLimit.notice(
            "측정창 등록 group=\(group.name, privacy: .public)#\(group.id.uuidString.prefix(4), privacy: .public) baseline=\(baseline, privacy: .public)m remaining=\(remaining, privacy: .public)m thresholds=\(thresholds.count, privacy: .public) gen=\(generation, privacy: .public)"
        )
    }

    /// 개별 그룹의 모니터링 자격. **드리프트 방지를 위해 범위를 재작성하지 않고 Domain 정책을 그대로
    /// 재사용**한다(`ScreenTimeGroupPolicy.invalidReason` → TimeWindowPolicy/CooldownPolicy 위임).
    /// dailyLimit 0분도 valid라 포함된다(즉시 잠금은 재등록 호출부가 `used>=limit`로 처리).
    /// union `maxShieldApplicationCount` 검사는 저장 시 `firstInvalidReason(for groups:)`의 몫이라
    /// 여기 per-group 자격에는 없음 — 자정 재등록은 이미 저장된 그룹 대상이므로 올바르다.
    nonisolated static func isTrackable(_ group: SharedStore.ScreenTimeGroup) -> Bool {
        ScreenTimeGroupPolicy.invalidReason(for: group.policySnapshot) == nil
    }

    /// 자정 하트비트가 필요한 구성인지. **daily/cooldown 그룹이 하나라도 있을 때만** 필요하다.
    /// - 시간대(timeWindows) 그룹은 window activity가 `repeats:true`라 자정 재무장이 원래 필요 없다.
    /// - 시간대 그룹은 window 최대 3개 + 연장 override까지 **그룹당 최대 4개** activity를 쓸 수 있어,
    ///   `maxGroupCount`(5) 전부가 시간대면 4×5=20으로 DeviceActivity 동시 모니터링 상한에 닿는다.
    ///   여기에 하트비트(+1)를 더하면 넘칠 수 있으므로, 불필요한 시간대-only 구성에선 등록하지 않는다.
    /// 유효(모니터링 대상) 그룹 목록을 넘겨야 한다.
    nonisolated static func needsHeartbeat(for groups: [SharedStore.ScreenTimeGroup]) -> Bool {
        groups.contains { $0.ruleKind == .dailyLimit || $0.ruleKind == .cooldown }
    }
}

/// 사용량 알림 정책 — 일일 한도·쿨다운 예산·연장분이 **공통으로** 쓴다(메인 앱·extension 공유).
/// 비율을 따로 계산하지 않고, 이미 등록된 threshold 틱 배열(`dailyThresholdMinutes`/
/// `usageThresholds`, 한도≤10분이면 1분 단위·≥10분이면 10개 균등분배)의 **인덱스**로 알림
/// 단계를 정한다. 그래서 등록된 측정 틱과 알림 시점이 어긋나지 않는다.
enum UsageAlertPolicy {
    /// 정렬된 threshold 틱 배열에서 발송할 (단계 percent, 절대 minute) 목록.
    /// - 틱 1개(1분): `[]` — 알림 없음
    /// - 틱 2~9개(2~9분): `[(90, 마지막 직전 틱)]` — 거의 다 썼을 때 1회
    /// - 틱 10개(10분 이상): `[(50, 5번째 틱), (90, 9번째 틱)]`
    /// percent는 문구 분기·중복방지 키로만 쓰고(짧은 한도의 단일 알림은 90으로 통일), 발화
    /// 판정은 minute(절대 사용량)으로 한다.
    nonisolated static func ticks(_ thresholdTicks: [Int]) -> [(percent: Int, minute: Int)] {
        let count = thresholdTicks.count
        guard count >= 2 else { return [] }
        if count >= 10 {
            return [(50, thresholdTicks[4]), (90, thresholdTicks[8])]
        }
        return [(90, thresholdTicks[count - 2])]
    }
}
