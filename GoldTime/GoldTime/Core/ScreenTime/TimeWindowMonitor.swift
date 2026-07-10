//
//  TimeWindowMonitor.swift
//  GoldTime
//
//  시간대 차단 모드의 DeviceActivity 이름 규약과 등록을 메인 앱과 extension이 공유한다.
//  (extension은 ScreenTimeManager를 포함하지 않으므로, 자정 요일 전환 시 오늘 시간대로
//  window activity를 재등록하려면 등록 로직을 공유해야 한다. 그래서 이 파일은 두 타겟 모두에
//  포함된다 — CooldownMonitor/DailyMonitor와 동일한 이유.)
//
//  ⚠️ 여기 있는 DeviceActivityName 헬퍼(timeWindow/timeWindowGroupID)는 공유 단일 출처다.
//  ScreenTimeManager나 DeviceActivityMonitorExtension에 같은 멤버를 다시 선언하면 두 타겟에서
//  중복 선언이 된다.
//

import DeviceActivity
import FamilyControls
import Foundation
import os

extension DeviceActivityName {
    /// `window.<UUID>.<index>` 형식. index는 그룹 timeWindows 배열 순서(0...).
    nonisolated static func timeWindow(for groupID: UUID, index: Int) -> Self {
        Self("window.\(groupID.uuidString).\(index)")
    }

    /// `window.<UUID>.<index>`에서 groupID 추출.
    var timeWindowGroupID: UUID? {
        let prefix = "window."
        guard rawValue.hasPrefix(prefix) else { return nil }
        let body = String(rawValue.dropFirst(prefix.count))
        let firstSegment = body.split(separator: ".").first.map(String.init) ?? body
        return UUID(uuidString: firstSegment)
    }
}

/// 시간대 차단 모드 DeviceActivity 등록 헬퍼. 메인 앱(ScreenTimeManager)과 extension이 공유.
enum TimeWindowMonitor {
    /// 한 그룹이 가질 수 있는 시간대 최대 개수(TimeWindowPolicy와 동일). 그룹이 시간대를 줄이거나
    /// 다른 규칙으로 바뀌어도 잔여 window activity가 남지 않도록, 정리 시 0...max-1을 전부 stop한다.
    static let maxTimeWindowsPerGroup = 3

    /// 그룹의 모든 시간대 슬롯 activity 이름(0..<max). 시간대가 줄거나 규칙(요일 전환 포함)이 바뀌어도
    /// 잔여 window activity가 repeats:true로 계속 발화하지 않도록 정리 시 전부 stop하는 데 쓴다.
    /// 미등록 슬롯 stop은 no-op라 무해하다.
    nonisolated static func allWindowActivities(for groupID: UUID) -> [DeviceActivityName] {
        (0..<maxTimeWindowsPerGroup).map { DeviceActivityName.timeWindow(for: groupID, index: $0) }
    }

    /// inclusive 종료분(E)을 스케줄 intervalEnd(차단 종료 순간 = E+1)로 변환한다.
    /// E가 23:59(1439)면 다음 분이 24:00(DateComponents hour:24 불가)이라 dailySchedule과 동일하게
    /// 23:59:59(하루의 끝)로 표현한다.
    nonisolated static func intervalEnd(forInclusiveEndMinute end: Int) -> DateComponents {
        let exclusiveEnd = end + 1
        guard exclusiveEnd < 24 * 60 else {
            return DateComponents(hour: 23, minute: 59, second: 59)
        }
        return DateComponents(hour: exclusiveEnd / 60, minute: exclusiveEnd % 60)
    }

    /// 시간대 차단 그룹을 timeWindows 개수만큼 window activity로 등록한다.
    /// TimeWindow의 endMinuteOfDay는 inclusive(차단되는 마지막 분)이므로 스케줄의 intervalEnd는
    /// "차단이 끝나는 순간" = endMinuteOfDay + 1로 변환한다(예: 12:59 차단 → intervalEnd 13:00).
    /// 각 시간대는 repeats:true로 돌고 threshold 이벤트는 없다(잠금은 intervalDidStart에서 resync로,
    /// 해제는 intervalDidEnd에서 resync로 처리). 요일별 그룹은 group에 오늘 투영본을 넘긴다.
    nonisolated static func startWindowMonitoring(
        center: DeviceActivityCenter,
        group: SharedStore.ScreenTimeGroup
    ) throws {
        for (index, window) in group.timeWindows.enumerated() {
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(
                    hour: window.startMinuteOfDay / 60,
                    minute: window.startMinuteOfDay % 60
                ),
                intervalEnd: intervalEnd(forInclusiveEndMinute: window.endMinuteOfDay),
                repeats: true
            )
            try center.startMonitoring(
                .timeWindow(for: group.id, index: index),
                during: schedule,
                events: [:]
            )
        }
        GTLog.timeWindow.notice(
            "시간대 window 등록 group=\(group.name, privacy: .public)#\(group.id.uuidString.prefix(4), privacy: .public) windows=\(group.timeWindows.count, privacy: .public)"
        )
    }
}
