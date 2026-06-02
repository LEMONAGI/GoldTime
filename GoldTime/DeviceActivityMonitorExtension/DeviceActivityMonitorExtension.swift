//
//  DeviceActivityMonitorExtension.swift
//  DeviceActivityMonitorExtension
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

extension DeviceActivityName {
    static let daily = Self("daily")

    /// 옛 형식(`daily.<UUID>`)과 새 형식(`daily.<UUID>.<gen>`) 모두 인식.
    var dailyGroupID: UUID? {
        let prefix = "daily."
        guard rawValue.hasPrefix(prefix), rawValue != "daily" else { return nil }
        let body = String(rawValue.dropFirst(prefix.count))
        let firstSegment = body.split(separator: ".").first.map(String.init) ?? body
        return UUID(uuidString: firstSegment)
    }

    var overrideGroupID: UUID? {
        let prefix = "override."
        guard rawValue.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(rawValue.dropFirst(prefix.count)))
    }
}

extension DeviceActivityEvent.Name {
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

    var usageTickInfo: (groupID: UUID, minute: Int)? {
        let prefix = "usageTick."
        guard rawValue.hasPrefix(prefix) else { return nil }
        let body = rawValue.dropFirst(prefix.count)
        let parts = body.split(separator: ".")
        guard parts.count == 2,
              let groupID = UUID(uuidString: String(parts[0])),
              let minute = Int(parts[1]) else { return nil }
        return (groupID, minute)
    }
}

extension ManagedSettingsStore.Name {
    static let goldtime = Self("goldtime")
}

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private var store: ManagedSettingsStore { ManagedSettingsStore(named: .goldtime) }

    private var dailySchedule: DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
    }


    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity.dailyGroupID != nil {
            if SharedStore.resetDailyProtectionStateIfNeeded() {
                clearSystemShield()
            }
            // 자정에 정확히 도는 콜백. 어제 데이터가 확정된 시점에 오늘 9시 알림을 예약한다.
            // 그룹 수만큼 호출돼도 SharedStore 가드가 하루 1회만 통과시킨다.
            NotificationService.scheduleDailyMorningNotificationIfNeeded()
        } else if activity.overrideGroupID != nil {
            SharedStore.recordOverrideIntervalDidStart(activityName: activity.rawValue)
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == .daily || activity.dailyGroupID != nil {
            // daily 계열은 dailySchedule(repeats:true)이 매일 자동 재시작하므로 무시.
            return
        }
        let result = SharedStore.clearOverrideAfterActivityEnd(activityName: activity.rawValue)
        SharedStore.recordOverrideIntervalDidEnd(
            activityName: activity.rawValue,
            parsedGroupID: result.parsedGroupID,
            didClearOverride: result.didClearOverride
        )
        applyShieldFromGroups()
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        guard activity.overrideGroupID != nil else { return }

        let result = SharedStore.clearOverrideAfterActivityEnd(activityName: activity.rawValue)
        SharedStore.recordOverrideIntervalWillEndWarning(
            activityName: activity.rawValue,
            parsedGroupID: result.parsedGroupID,
            didClearOverride: result.didClearOverride
        )
        applyShieldFromGroups()
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)

        // 사용량 기반 override tick: 광고/1분 연장 중 그룹의 앱을 minute분 누적 사용 시 1회 발동.
        if let info = event.usageTickInfo {
            handleOverrideTick(groupID: info.groupID, minute: info.minute, activity: activity)
            return
        }

        // no-relay multi-event: tick.<gid>.<minute>가 등록 시점부터 누적 minute분 사용 시 1회 발화.
        guard let info = event.tickInfo,
              activity.dailyGroupID == info.groupID else { return }
        let groupID = info.groupID

        // 자정을 넘겨 계속 사용 중인 경우 일일 리셋(usedTime 0) 처리.
        if SharedStore.resetDailyProtectionStateIfNeeded() {
            clearSystemShield()
        }

        guard let group = SharedStore.group(id: groupID) else { return }

        // 틱 분은 baseline(등록 시점 usedTime) 기준 상대값이므로 절대 사용량으로 복원해 올린다(역행 방지).
        // 한도 변경으로 재등록되어도 baseline이 보존되므로 이미 쓴 분이 유지된다.
        let baseline = SharedStore.dailyBaselineByGroupID[groupID] ?? 0
        let usedTime = SharedStore.raiseUsedTime(to: baseline + info.minute, for: groupID)
        let isOverrideActive = SharedStore.usageBasedOverrideGroupIDs.contains(groupID)
        let willLock = usedTime >= group.dailyLimitMinutes && !isOverrideActive

        if willLock {
            SharedStore.recordShieldHit()
            SharedStore.markGroupShielded(groupID)
            applyShieldFromGroups()
        }
    }

    private func handleOverrideTick(groupID: UUID, minute: Int, activity: DeviceActivityName) {
        let baseline = SharedStore.overrideBaselineUsedTimeByGroupID[groupID] ?? 0
        let granted = SharedStore.overrideGrantedMinutesByGroupID[groupID] ?? 1

        // 이 이벤트는 override 시작부터 누적 `minute`분 사용 시 1회 발화한다.
        // usedTime을 baseline+minute 이상으로만 올려 UI 잔여 시간을 갱신한다 (재등록 없음).
        let usedTime = SharedStore.raiseUsedTime(to: baseline + minute, for: groupID)

        guard minute >= granted else { return }

        // 연장분 소진: 재잠금
        let center = DeviceActivityCenter()
        center.stopMonitoring([activity])
        SharedStore.clearOverride(for: groupID)
        SharedStore.markGroupShielded(groupID)
        SharedStore.recordOverrideIntervalDidEnd(
            activityName: activity.rawValue,
            parsedGroupID: groupID,
            didClearOverride: true
        )
        applyShieldFromGroups()
    }

    @discardableResult
    private func applyShieldFromGroups() -> Int {
        let applicationTokens = SharedStore.shieldApplicationTokens()
        let webDomainTokens = SharedStore.shieldWebDomainTokens()
        let tokenCount = applicationTokens.count + webDomainTokens.count
        guard tokenCount > 0 else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            SharedStore.isShieldActive = false
            SharedStore.recordOverrideReapply(
                tokenCount: 0,
                message: "cleared shield because token union is empty"
            )
            return 0
        }

        store.shield.applications = applicationTokens.isEmpty ? nil : applicationTokens
        store.shield.applicationCategories = nil
        store.shield.webDomains = webDomainTokens.isEmpty ? nil : webDomainTokens
        SharedStore.isShieldActive = true
        SharedStore.recordOverrideReapply(
            tokenCount: tokenCount,
            message: "applied shield from locked groups"
        )
        return tokenCount
    }

    private func clearSystemShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
    }
}
