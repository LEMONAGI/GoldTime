//
//  DeviceActivityMonitorExtension.swift
//  DeviceActivityMonitorExtension
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

// daily/dailyGroup/dailyGroupID/dailyHeartbeat 및 DeviceActivityEvent.Name.tick/tickInfo는
// DailyMonitor.swift(공유)에 정의됨. 여기서 다시 선언하면 두 타겟에서 중복 선언이 된다.
extension DeviceActivityName {
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

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity == .dailyHeartbeat {
            // 자정 리셋·재무장의 주 경로(repeats:true라 매일 00:00 발화).
            handleHeartbeat()
        } else if activity.timeWindowGroupID != nil {
            // 시간대 진입. 하트비트가 자정 리셋의 주 경로지만, 이중 안전망으로 여기서도 점검한다.
            if SharedStore.resetDailyProtectionStateIfNeeded() {
                clearSystemShield()
            }
            let result = SharedStore.resyncTimeWindowLocks()
            if !result.newlyLocked.isEmpty {
                SharedStore.recordShieldHit()
                SharedStore.enqueueShieldHit(ruleKind: "timeWindows")
            }
            applyShieldFromGroups()
        } else if activity.overrideGroupID != nil {
            SharedStore.recordOverrideIntervalDidStart(activityName: activity.rawValue)
        }
    }

    /// 자정 하트비트(`dailyHeartbeat`, repeats:true) 발화. 날짜가 실제로 바뀐 경우(didReset)에만
    /// 일일 리셋 + daily/cooldown 모니터 재무장 + 아침 알림 예약을 한다. 같은 날 등록 직후에도
    /// 발화할 수 있으므로 didReset 가드로 불필요한 재등록·알림을 막는다.
    private func handleHeartbeat() {
        // generation은 리셋 *전에* 스냅샷한다 — resetDailyProtectionStateIfNeeded()가
        // clearAllUsedTime()으로 lastRegisteredGenerationByID를 비우기 때문(daily gen 손실 방지).
        let dailyGenSnapshot = SharedStore.lastRegisteredGenerationByID
        let cooldownGenSnapshot = SharedStore.cooldownGenerationByID

        guard SharedStore.resetDailyProtectionStateIfNeeded() else { return }

        // 어제 데이터 확정 시점에 오늘 9시 알림 예약(SharedStore 가드가 하루 1회만 통과).
        NotificationService.scheduleDailyMorningNotificationIfNeeded()
        clearSystemShield()

        let center = DeviceActivityCenter()
        var dailyGens = SharedStore.lastRegisteredGenerationByID   // 리셋으로 [:]
        var cooldownGens = SharedStore.cooldownGenerationByID
        var registered: [UUID: SharedStore.ScreenTimeGroup] = [:]

        for group in SharedStore.screenTimeGroups where DailyMonitor.isTrackable(group) {
            switch group.ruleKind {
            case .dailyLimit:
                // 즉시 잠금/등록 양쪽 모두 old activity stop + generation bump를 무조건 먼저.
                let oldGen = dailyGenSnapshot[group.id] ?? 0
                center.stopMonitoring([.dailyGroup(for: group.id, generation: oldGen)])
                let newGen = oldGen + 1
                dailyGens[group.id] = newGen
                let used = SharedStore.usedTimeByGroupID[group.id] ?? 0
                if used >= group.dailyLimitMinutes {
                    // 0분 그룹 등 즉시 잠금: 모니터 없이 잠금만(리셋 직후 used=0이라 실질 limit==0).
                    SharedStore.markGroupShielded(group.id)
                    registered[group.id] = group
                } else {
                    // 등록 성공 시에만 registered에 기록한다. 실패한 그룹을 기록하면
                    // lastRegisteredGroupsByID 기반 churn 가드가 foreground 재등록을 영구 스킵하고
                    // 대시보드가 미추적을 정상으로 오표시한다(메인 앱 syncDailyMonitoring과 동일 계약).
                    do {
                        try DailyMonitor.startUsageMonitoring(center: center, group: group, generation: newGen)
                        registered[group.id] = group
                    } catch {
                        SharedStore.enqueueScreenTimeError(context: "heartbeatDaily", message: error.localizedDescription)
                    }
                }
            case .cooldown:
                let oldGen = cooldownGenSnapshot[group.id] ?? 0
                center.stopMonitoring([
                    .cooldownUsage(for: group.id, generation: oldGen),
                    .cooldownTimer(for: group.id)
                ])
                let newGen = oldGen + 1
                cooldownGens[group.id] = newGen
                if group.cooldownUsageMinutes > 0 {
                    // dailyLimit과 동일: 등록 성공 시에만 registered에 기록(실패 그룹 박제 방지).
                    do {
                        try CooldownMonitor.startUsageMonitoring(center: center, group: group, generation: newGen)
                        registered[group.id] = group
                    } catch {
                        SharedStore.enqueueScreenTimeError(context: "heartbeatCooldown", message: error.localizedDescription)
                    }
                } else {
                    registered[group.id] = group
                }
            case .timeWindows:
                // window activity는 repeats:true로 살아 있어 재등록하지 않는다. 다음 앱 sync의
                // churn을 줄이려고 등록 기록만 복원한다.
                registered[group.id] = group
            case .none:
                break
            }
        }

        SharedStore.lastRegisteredGenerationByID = dailyGens
        SharedStore.cooldownGenerationByID = cooldownGens
        SharedStore.lastRegisteredGroupsByID = registered

        SharedStore.resyncTimeWindowLocks()
        applyShieldFromGroups()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == .daily || activity == .dailyHeartbeat || activity.dailyGroupID != nil {
            // 하트비트(repeats:true)는 23:59:59 종료 후 00:00에 다시 시작하고, daily 측정창은
            // 자정 하트비트가 재무장하므로 둘 다 종료를 무시한다.
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
        // tick 분은 cooldown baseline(등록 시점 usedTime) 기준 상대값이므로
        // 사이클 전체 사용량으로 복원해 올린다(역행 방지).
        let baseline = SharedStore.cooldownBaselineByGroupID[groupID] ?? 0
        let used = SharedStore.raiseUsedTime(
            to: CooldownMonitor.absoluteUsedMinutes(baseline: baseline, tickMinute: minute),
            for: groupID
        )

        // 이미 휴식 중이거나 결제(override) 중이면 잠금 트리거를 건너뛴다(진행만 갱신).
        guard !SharedStore.isInCooldown(groupID),
              !SharedStore.usageBasedOverrideGroupIDs.contains(groupID) else { return }
        // 아직 예산이 남았으면 진행바만 갱신하고 끝.
        guard used >= group.cooldownUsageMinutes else { return }

        let now = Date()
        let until = CooldownMonitor.cooldownEnd(now: now, durationMinutes: group.cooldownDurationMinutes)
        SharedStore.startCooldown(until: until, for: groupID)
        SharedStore.recordShieldHit()
        SharedStore.enqueueShieldHit(ruleKind: "cooldown")
        do {
            try CooldownMonitor.startCooldownTimer(
                center: DeviceActivityCenter(),
                groupID: groupID,
                until: until,
                now: now
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
        // 자정 리셋 등으로 이미 휴식이 풀렸거나(cooldownEnd == nil), 설정 변경 재동기화 등으로
        // 타이머가 휴식 종료 예정 시각보다 일찍 멈춘 경우(cooldownEnd > now)에는 재충전하지 않고
        // Shield만 다시 적용해 현재 휴식을 보존한다. nil과 미래는 둘 다 재충전 금지지만 의미가
        // 달라 단일 가드로 합치지 않는다(isInCooldown은 nil도 false라 합치면 nil일 때 통과한다).
        guard SharedStore.cooldownEnd(for: groupID) != nil else {
            applyShieldFromGroups()
            return
        }
        guard CooldownMonitor.shouldRechargeOnTimerEnd(
            cooldownEnd: SharedStore.cooldownEnd(for: groupID),
            now: Date()
        ) else {
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
                // 무증상으로 삼키지 않고 기록한다. 그리고 churn 가드를 무효화해 다음 foreground sync가
                // 재등록하게 한다 — 이 경로는 lastRegisteredGroupsByID를 건드리지 않아 last==group이
                // 남고 syncDailyMonitoring이 그룹을 스킵, 자정 하트비트까지(~최대 24h) 재등록되지 못한다.
                // foreground 자가치유(ScreenTimeManager.rechargeExpiredCooldowns)·하트비트 경로와 동일 계약.
                SharedStore.enqueueScreenTimeError(
                    context: "cooldownRecharge",
                    message: error.localizedDescription
                )
                SharedStore.clearRegistration(for: groupID)
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
