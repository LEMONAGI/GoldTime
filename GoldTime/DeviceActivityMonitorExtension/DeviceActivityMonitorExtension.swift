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

    /// `window.<UUID>.<index>`에서 groupID 추출 (시간대 차단 activity).
    var timeWindowGroupID: UUID? {
        let prefix = "window."
        guard rawValue.hasPrefix(prefix) else { return nil }
        let body = String(rawValue.dropFirst(prefix.count))
        let firstSegment = body.split(separator: ".").first.map(String.init) ?? body
        return UUID(uuidString: firstSegment)
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
        if activity.timeWindowGroupID != nil {
            // 시간대 진입. 모든 그룹이 시간대 규칙이면 daily activity가 없어 자정 리셋 트리거가
            // 사라지므로 여기서도 리셋을 점검한다.
            if SharedStore.resetDailyProtectionStateIfNeeded() {
                clearSystemShield()
            }
            let result = SharedStore.resyncTimeWindowLocks()
            if !result.newlyLocked.isEmpty {
                SharedStore.recordShieldHit()
                SharedStore.enqueueShieldHit(ruleKind: "timeWindows")
            }
            applyShieldFromGroups()
        } else if activity.dailyGroupID != nil {
            if SharedStore.resetDailyProtectionStateIfNeeded() {
                clearSystemShield()
                // 00:00 시작 시간대와 자정 리셋의 race 보완: 리셋 직후 시간대 잠금을 다시 반영한다.
                SharedStore.resyncTimeWindowLocks()
                applyShieldFromGroups()
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
        // 시간대 종료. daily가 아닌 activity는 아래에서 전부 override로 처리되므로 먼저 가로챈다.
        if activity.timeWindowGroupID != nil {
            SharedStore.resyncTimeWindowLocks()
            applyShieldFromGroups()
            return
        }
        // 쿨다운 사용 예산 창은 23:59:59에 자연 종료된다(daily처럼 무시 — 자정 리셋이 재등록).
        if activity.cooldownUsageGroupID != nil {
            return
        }
        // 휴식 타이머 종료 → 재충전(사용 예산 모니터 재등록).
        if let groupID = activity.cooldownTimerGroupID {
            handleCooldownTimerEnded(groupID: groupID)
            return
        }
        let result = SharedStore.clearOverrideAfterActivityEnd(activityName: activity.rawValue)
        SharedStore.recordOverrideIntervalDidEnd(
            activityName: activity.rawValue,
            parsedGroupID: result.parsedGroupID,
            didClearOverride: result.didClearOverride
        )
        // override 종료 시점에 시간대가 이미 끝난 그룹이 잘못 재잠금되지 않도록 보정한다.
        SharedStore.resyncTimeWindowLocks()
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
        SharedStore.resyncTimeWindowLocks()
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

        // 쿨다운 사용 예산 tick: 진행바용 사용량 갱신 + 예산 소진 시 잠금.
        if let info = event.cooldownTickInfo,
           activity.cooldownUsageGroupID == info.groupID {
            handleCooldownUsageTick(groupID: info.groupID, minute: info.minute)
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
            SharedStore.enqueueShieldHit(ruleKind: "dailyLimit")
            SharedStore.markGroupShielded(groupID)
            applyShieldFromGroups()
        }
    }

    private func handleOverrideTick(groupID: UUID, minute: Int, activity: DeviceActivityName) {
        if SharedStore.resetDailyProtectionStateIfNeeded() {
            clearSystemShield()
        }
        guard SharedStore.usageBasedOverrideGroupIDs.contains(groupID),
              SharedStore.overrideUntilByGroupID[groupID] != nil else {
            DeviceActivityCenter().stopMonitoring([activity])
            SharedStore.recordOverrideIntervalDidEnd(
                activityName: activity.rawValue,
                parsedGroupID: groupID,
                didClearOverride: false
            )
            applyShieldFromGroups()
            return
        }

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
        // 연장 소진 재잠금 직후, 시간대가 이미 끝난 시간대 그룹은 다시 풀어준다
        // (dailyLimit 그룹의 재잠금에는 영향 없음 — resync는 timeWindows 그룹만 건드림).
        SharedStore.resyncTimeWindowLocks()
        applyShieldFromGroups()
    }

    /// 쿨다운 사용 예산 tick → 진행바용 사용량 갱신, 예산(cooldownUsageMinutes) 소진 시 잠금.
    private func handleCooldownUsageTick(groupID: UUID, minute: Int) {
        // 자정을 넘겨 계속 사용 중이면 일일 리셋 처리(쿨다운도 자정에 함께 해제됨).
        if SharedStore.resetDailyProtectionStateIfNeeded() {
            clearSystemShield()
        }
        guard let group = SharedStore.group(id: groupID) else { return }
        // 사이클 사용량을 minute로 끌어올린다(역행 방지) → 홈 진행바가 남은 시간을 보여준다.
        let used = SharedStore.raiseUsedTime(to: minute, for: groupID)

        // 이미 휴식 중이거나 결제(override) 중이면 잠금 트리거를 건너뛴다(진행만 갱신).
        guard !SharedStore.isInCooldown(groupID),
              !SharedStore.usageBasedOverrideGroupIDs.contains(groupID) else { return }
        // 아직 예산이 남았으면 진행바만 갱신하고 끝.
        guard used >= group.cooldownUsageMinutes else { return }

        let until = Date().addingTimeInterval(TimeInterval(group.cooldownDurationMinutes * 60))
        SharedStore.startCooldown(until: until, for: groupID)
        SharedStore.recordShieldHit()
        SharedStore.enqueueShieldHit(ruleKind: "cooldown")
        do {
            try CooldownMonitor.startCooldownTimer(
                center: DeviceActivityCenter(),
                groupID: groupID,
                until: until
            )
        } catch {
            SharedStore.enqueueScreenTimeError(
                context: "cooldownTimer",
                message: error.localizedDescription
            )
        }
        applyShieldFromGroups()
    }

    /// 휴식 타이머 종료 → 사용 예산 모니터를 새 generation으로 재등록(다음 사이클 시작) + 잠금 해제.
    private func handleCooldownTimerEnded(groupID: UUID) {
        if SharedStore.resetDailyProtectionStateIfNeeded() {
            clearSystemShield()
        }
        // 자정 리셋 등으로 이미 휴식이 풀렸으면 중복 재충전하지 않는다.
        guard SharedStore.cooldownEnd(for: groupID) != nil else {
            applyShieldFromGroups()
            return
        }
        let generation = SharedStore.endCooldownAndRecharge(for: groupID)
        let center = DeviceActivityCenter()
        // 직전 사이클의 사용 예산 activity를 멈춘 뒤 새 generation으로 재등록.
        center.stopMonitoring([.cooldownUsage(for: groupID, generation: generation - 1)])
        if let group = SharedStore.group(id: groupID), group.cooldownUsageMinutes > 0 {
            do {
                try CooldownMonitor.startUsageMonitoring(
                    center: center,
                    group: group,
                    generation: generation
                )
            } catch {
                SharedStore.enqueueScreenTimeError(
                    context: "cooldownRecharge",
                    message: error.localizedDescription
                )
            }
        }
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
