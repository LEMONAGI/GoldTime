//
//  DeviceActivityMonitorExtension.swift
//  DeviceActivityMonitorExtension
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import os

// daily/dailyGroup/dailyGroupID/dailyHeartbeat 및 DeviceActivityEvent.Name.tick/tickInfo는
// DailyMonitor.swift(공유)에, window.*/timeWindowGroupID는 TimeWindowMonitor.swift(공유)에
// 정의됨. 여기서 다시 선언하면 두 타겟에서 중복 선언이 된다.
extension DeviceActivityName {
    var overrideGroupID: UUID? {
        let prefix = "override."
        guard rawValue.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(rawValue.dropFirst(prefix.count)))
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
        // 콜백 진입점 raw 로깅: 어떤 activity가 시작됐는지(혹은 안 들어오는지) 자체를 추적한다.
        GTLog.activity.notice("▶︎ intervalDidStart activity=\(activity.rawValue, privacy: .public)")
        if activity == .dailyHeartbeat {
            // 자정 리셋·재무장의 주 경로(repeats:true라 매일 00:00 발화).
            handleHeartbeat()
        } else if let windowGroupID = activity.timeWindowGroupID {
            // 시간대 진입. 하트비트가 자정 리셋의 주 경로지만, 이중 안전망으로 여기서도 점검한다.
            if SharedStore.resetDailyProtectionStateIfNeeded() {
                clearSystemShield()
            }
            let result = SharedStore.resyncTimeWindowLocks()
            if !result.newlyLocked.isEmpty {
                GTLog.timeWindow.notice(
                    "시간대 진입 → 잠금 \(self.groupLabel(windowGroupID), privacy: .public) newlyLocked=\(result.newlyLocked.count, privacy: .public)"
                )
                SharedStore.recordShieldHit()
                SharedStore.enqueueShieldHit(ruleKind: "timeWindows")
            } else {
                GTLog.timeWindow.notice(
                    "시간대 진입했으나 잠금 변화 없음 \(self.groupLabel(windowGroupID), privacy: .public)"
                )
            }
            applyShieldFromGroups()
        } else if let overrideGroupID = activity.overrideGroupID {
            GTLog.override.notice("연장 측정창 시작 \(self.groupLabel(overrideGroupID), privacy: .public)")
            SharedStore.recordOverrideIntervalDidStart(activityName: activity.rawValue)
        }
    }

    /// 로그용 그룹 라벨. 그룹 이름(없으면 "?") + UUID 앞 4자리. 토큰류 민감정보는 포함하지 않는다.
    private func groupLabel(_ id: UUID?) -> String {
        guard let id else { return "?" }
        let name = SharedStore.group(id: id)?.name ?? "?"
        return "\(name)#\(id.uuidString.prefix(4))"
    }

    /// 자정 하트비트(`dailyHeartbeat`, repeats:true) 발화. 날짜가 실제로 바뀐 경우(didReset)에만
    /// 일일 리셋 + daily/cooldown 모니터 재무장 + 아침 알림 예약을 한다. 같은 날 등록 직후에도
    /// 발화할 수 있으므로 didReset 가드로 불필요한 재등록·알림을 막는다.
    private func handleHeartbeat() {
        // generation·등록 기록은 리셋 *전에* 스냅샷한다 — resetDailyProtectionStateIfNeeded()가
        // clearAllUsedTime()으로 lastRegisteredGenerationByID와 lastRegisteredGroupsByID를 비우기
        // 때문(daily gen 손실 방지). registeredBeforeReset은 "어제 실제 등록된 종류/시간대"의 단일
        // 출처로, 요일 전환 시 시간대 window를 무중단 유지할지 재등록할지 판정하는 데 쓴다.
        let dailyGenSnapshot = SharedStore.lastRegisteredGenerationByID
        let cooldownGenSnapshot = SharedStore.cooldownGenerationByID
        let registeredBeforeReset = SharedStore.lastRegisteredGroupsByID ?? [:]

        guard SharedStore.resetDailyProtectionStateIfNeeded() else {
            GTLog.shield.notice("하트비트 발화했으나 날짜 변화 없음 → 재무장 스킵")
            return
        }
        GTLog.shield.notice("자정 리셋 + 재무장 시작")

        let now = Date()
        // 어제 데이터 확정 시점에 오늘 9시 알림 예약(SharedStore 가드가 하루 1회만 통과).
        NotificationService.scheduleDailyMorningNotificationIfNeeded(now: now)
        // 요일별 시간대 알림은 오늘 날짜 기준 일회성 예약이라, 자정 전환 때 다음 날분을 다시 건다.
        // 00:00~00:05 시작의 5분 전 알림은 전날 예약본이 담당한다.
        NotificationService.rescheduleTimeWindowAlerts(groups: SharedStore.screenTimeGroups, now: now)
        clearSystemShield()

        let center = DeviceActivityCenter()
        var dailyGens = SharedStore.lastRegisteredGenerationByID   // 리셋으로 [:]
        var cooldownGens = SharedStore.cooldownGenerationByID
        // registered에는 오늘 투영본을 저장한다(메인 앱 churn 가드가 오늘 규칙 기준으로 비교하게).
        var registered: [UUID: SharedStore.ScreenTimeGroup] = [:]

        for group in SharedStore.screenTimeGroups {
            // 오늘의 규칙으로 투영한 사본. 요일별 그룹은 오늘 규칙만 남고 weekdayRules가 스트립된다.
            let today = group.resolved(on: now)
            let usesWeekday = group.usesWeekdayRules
            let snapshot = registeredBeforeReset[group.id]

            // 요일 그룹은 오늘 kind와 무관하게 어제 kind의 daily/cooldown 측정창을 스냅샷 gen으로
            // 명시 stop하고 gen을 미리 올린다. date-less repeats:false 창의 자정 재무장은
            // undocumented지만 실제로 가능해(1.0.0 실증, Core/CLAUDE.md), 어제-cooldown →
            // 오늘-'제한 없음' 같은 kind 전환에서 stale tick이 오늘 규칙에 없는 잠금을 만들 수 있다.
            // gen을 올려두면 비daily/비cooldown 요일을 지나도 이름 연속성이 유지돼 과거 stop된
            // 이름 재사용(카운터 승계 회귀)도 막는다. 오늘 같은 kind를 재등록하는 아래 분기의
            // stop/bump와 겹쳐도 no-op·동일값이라 무해하고, 자정엔 휴식이 이미 리셋돼
            // cooldownTimer stop도 안전하다(휴식-중 stop 금지 규칙은 같은 날 편집에만 해당).
            if usesWeekday {
                let oldDailyGen = dailyGenSnapshot[group.id] ?? 0
                let oldCooldownGen = cooldownGenSnapshot[group.id] ?? 0
                center.stopMonitoring([
                    .dailyGroup(for: group.id, generation: oldDailyGen),
                    .cooldownUsage(for: group.id, generation: oldCooldownGen),
                    .cooldownTimer(for: group.id),
                ])
                dailyGens[group.id] = oldDailyGen + 1
                cooldownGens[group.id] = oldCooldownGen + 1
            }

            guard DailyMonitor.isTrackable(today) else {
                // 오늘 '제한 없음'(투영 ruleKind nil) 또는 draft/미적용 등 비추적 그룹. 요일 그룹이 어제
                // timeWindows였다면 repeats:true window activity가 계속 발화하므로 슬롯을 전부 멈춘다.
                if usesWeekday {
                    center.stopMonitoring(TimeWindowMonitor.allWindowActivities(for: group.id))
                    GTLog.timeWindow.notice(
                        "재무장: 요일 전환 오늘 비추적 → window 정리 \(self.groupLabel(group.id), privacy: .public)"
                    )
                }
                continue
            }

            switch today.ruleKind {
            case .dailyLimit:
                // 요일 전환(어제 window → 오늘 daily) 시 어제 window 잔재를 차단한다(no-op 무해).
                if usesWeekday { center.stopMonitoring(TimeWindowMonitor.allWindowActivities(for: group.id)) }
                // 즉시 잠금/등록 양쪽 모두 old activity stop + generation bump를 무조건 먼저.
                let oldGen = dailyGenSnapshot[group.id] ?? 0
                center.stopMonitoring([.dailyGroup(for: group.id, generation: oldGen)])
                let newGen = oldGen + 1
                dailyGens[group.id] = newGen
                let used = SharedStore.usedTimeByGroupID[group.id] ?? 0
                if used >= today.dailyLimitMinutes {
                    // 0분 그룹 등 즉시 잠금: 모니터 없이 잠금만(리셋 직후 used=0이라 실질 limit==0).
                    SharedStore.markGroupShielded(group.id)
                    registered[group.id] = today
                    GTLog.dailyLimit.notice(
                        "재무장: 즉시 잠금 \(self.groupLabel(group.id), privacy: .public) used=\(used, privacy: .public)/\(today.dailyLimitMinutes, privacy: .public)m gen=\(newGen, privacy: .public)"
                    )
                } else {
                    // 등록 성공 시에만 registered에 기록한다. 실패한 그룹을 기록하면
                    // lastRegisteredGroupsByID 기반 churn 가드가 foreground 재등록을 영구 스킵하고
                    // 대시보드가 미추적을 정상으로 오표시한다(메인 앱 syncDailyMonitoring과 동일 계약).
                    do {
                        try DailyMonitor.startUsageMonitoring(center: center, group: today, generation: newGen)
                        registered[group.id] = today
                        GTLog.dailyLimit.notice(
                            "재무장: 측정 등록 \(self.groupLabel(group.id), privacy: .public) limit=\(today.dailyLimitMinutes, privacy: .public)m gen=\(newGen, privacy: .public)"
                        )
                    } catch {
                        GTLog.dailyLimit.error(
                            "재무장: 측정 등록 실패 \(self.groupLabel(group.id), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                        )
                        SharedStore.enqueueScreenTimeError(context: "heartbeatDaily", message: error.localizedDescription)
                    }
                }
            case .cooldown:
                if usesWeekday { center.stopMonitoring(TimeWindowMonitor.allWindowActivities(for: group.id)) }
                let oldGen = cooldownGenSnapshot[group.id] ?? 0
                center.stopMonitoring([
                    .cooldownUsage(for: group.id, generation: oldGen),
                    .cooldownTimer(for: group.id)
                ])
                let newGen = oldGen + 1
                cooldownGens[group.id] = newGen
                if today.cooldownUsageMinutes > 0 {
                    // dailyLimit과 동일: 등록 성공 시에만 registered에 기록(실패 그룹 박제 방지).
                    do {
                        try CooldownMonitor.startUsageMonitoring(center: center, group: today, generation: newGen)
                        registered[group.id] = today
                        GTLog.cooldown.notice(
                            "재무장: 예산 측정 등록 \(self.groupLabel(group.id), privacy: .public) budget=\(today.cooldownUsageMinutes, privacy: .public)m gen=\(newGen, privacy: .public)"
                        )
                    } catch {
                        GTLog.cooldown.error(
                            "재무장: 예산 측정 등록 실패 \(self.groupLabel(group.id), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                        )
                        SharedStore.enqueueScreenTimeError(context: "heartbeatCooldown", message: error.localizedDescription)
                    }
                } else {
                    registered[group.id] = today
                }
            case .timeWindows:
                // 어제 스냅샷 종류·시간대 구성이 오늘과 같으면 window activity(repeats:true)를 무중단
                // 유지하고 등록 기록만 복원한다(churn 감소). 요일이 바뀌며 구성이 달라졌거나 어제가 다른
                // 규칙이었으면 슬롯을 전부 stop하고 오늘 시간대로 재등록한다(window는 이벤트 없는 스케줄이라
                // 이름 재사용 시 threshold 회귀 무관).
                if snapshot?.ruleKind == .timeWindows, snapshot?.timeWindows == today.timeWindows {
                    registered[group.id] = today
                    GTLog.timeWindow.notice(
                        "재무장: 시간대 구성 동일 → 등록 기록만 복원 \(self.groupLabel(group.id), privacy: .public)"
                    )
                } else {
                    center.stopMonitoring(TimeWindowMonitor.allWindowActivities(for: group.id))
                    do {
                        try TimeWindowMonitor.startWindowMonitoring(center: center, group: today)
                        registered[group.id] = today
                        GTLog.timeWindow.notice(
                            "재무장: 요일 전환 window 재등록 \(self.groupLabel(group.id), privacy: .public) windows=\(today.timeWindows.count, privacy: .public)"
                        )
                    } catch {
                        GTLog.timeWindow.error(
                            "재무장: window 재등록 실패 \(self.groupLabel(group.id), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                        )
                        SharedStore.enqueueScreenTimeError(context: "heartbeatTimeWindow", message: error.localizedDescription)
                    }
                }
            case .none:
                break   // isTrackable(today) 가드가 걸러내므로 도달 불가.
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
        GTLog.activity.notice("■ intervalDidEnd activity=\(activity.rawValue, privacy: .public)")
        if activity == .daily || activity == .dailyHeartbeat || activity.dailyGroupID != nil {
            // 하트비트(repeats:true)는 23:59:59 종료 후 00:00에 다시 시작하고, daily 측정창은
            // 자정 하트비트가 재무장하므로 둘 다 종료를 무시한다.
            return
        }
        // 시간대 종료. daily가 아닌 activity는 아래에서 전부 override로 처리되므로 먼저 가로챈다.
        if let windowGroupID = activity.timeWindowGroupID {
            GTLog.timeWindow.notice("시간대 종료 → 해제 점검 \(self.groupLabel(windowGroupID), privacy: .public)")
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
            GTLog.cooldown.notice("휴식 타이머 종료 → 재충전 시도 \(self.groupLabel(groupID), privacy: .public)")
            handleCooldownTimerEnded(groupID: groupID)
            return
        }
        let result = SharedStore.clearOverrideAfterActivityEnd(activityName: activity.rawValue)
        GTLog.override.notice(
            "연장 측정창 종료 \(self.groupLabel(result.parsedGroupID), privacy: .public) cleared=\(result.didClearOverride, privacy: .public)"
        )
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
        GTLog.activity.notice("⚠︎ intervalWillEndWarning activity=\(activity.rawValue, privacy: .public)")
        guard activity.overrideGroupID != nil else { return }

        let result = SharedStore.clearOverrideAfterActivityEnd(activityName: activity.rawValue)
        GTLog.override.notice(
            "연장 종료 임박 → 해제 \(self.groupLabel(result.parsedGroupID), privacy: .public) cleared=\(result.didClearOverride, privacy: .public)"
        )
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
        // 모든 tick(tick.*/cdtick.*/usageTick.*)이 파싱 분기로 갈리기 전에 여기서 한 번 다 찍힌다.
        // "사용량이 측정되는지" = "tick이 도착하는지"의 1차 증거.
        GTLog.activity.notice(
            "● eventDidReachThreshold event=\(event.rawValue, privacy: .public) activity=\(activity.rawValue, privacy: .public)"
        )

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

        // 오늘 규칙 기준으로 잠금/알림을 판정한다(요일별 그룹은 오늘 한도로 투영).
        guard let group = SharedStore.resolvedGroup(id: groupID) else { return }
        // 오늘 규칙이 일일 한도가 아니면 stale tick으로 간주하고 무시한다 — 어제 측정창의 자정
        // 재무장(undocumented)이나 규칙 편집 직후 race로 늦게 도착한 tick이 오늘 규칙에 없는
        // 잠금을 만들면 안 된다(요일 전환 심층 방어).
        guard group.ruleKind == .dailyLimit else {
            GTLog.dailyLimit.notice(
                "stale daily tick 무시(오늘 규칙 불일치) \(self.groupLabel(groupID), privacy: .public)"
            )
            return
        }

        // 틱 분은 baseline(등록 시점 usedTime) 기준 상대값이므로 절대 사용량으로 복원해 올린다(역행 방지).
        // 한도 변경으로 재등록되어도 baseline이 보존되므로 이미 쓴 분이 유지된다.
        let baseline = SharedStore.dailyBaselineByGroupID[groupID] ?? 0
        let usedTime = SharedStore.raiseUsedTime(to: baseline + info.minute, for: groupID)
        let isOverrideActive = SharedStore.usageBasedOverrideGroupIDs.contains(groupID)
        // 한도 임박 알림은 연장(override) 중이 아닐 때만(연장은 별도 override 경로가 담당).
        if !isOverrideActive {
            emitUsageAlerts(groupID: groupID, used: usedTime, limit: group.dailyLimitMinutes, kind: .daily)
        }
        let willLock = usedTime >= group.dailyLimitMinutes && !isOverrideActive
        GTLog.dailyLimit.notice(
            "사용 측정 \(self.groupLabel(groupID), privacy: .public) used=\(usedTime, privacy: .public)/\(group.dailyLimitMinutes, privacy: .public)m override=\(isOverrideActive, privacy: .public) willLock=\(willLock, privacy: .public)"
        )

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
            // stale tick: 자정 리셋 등으로 override metadata가 사라진 뒤 늦게 도착한 tick.
            GTLog.override.notice("연장 stale tick 무시 \(self.groupLabel(groupID), privacy: .public) minute=\(minute, privacy: .public)")
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
        // 연장분(granted) 기준 50·90% 임박 알림. granted=1이면 알림 없음, 10이면 둘 다(UsageAlertPolicy).
        emitUsageAlerts(groupID: groupID, used: minute, limit: granted, kind: .override)
        GTLog.override.notice(
            "연장 사용 측정 \(self.groupLabel(groupID), privacy: .public) used=\(minute, privacy: .public)/\(granted, privacy: .public)m total=\(usedTime, privacy: .public)m"
        )

        guard minute >= granted else { return }
        GTLog.override.notice("연장분 소진 → 재잠금 \(self.groupLabel(groupID), privacy: .public)")

        // 연장분 소진: 재잠금
        let center = DeviceActivityCenter()
        center.stopMonitoring([activity])
        SharedStore.clearOverride(for: groupID)
        // 쿨다운 그룹은 휴식이 이미 재충전된 뒤 살아남은 연장의 소진이면 재잠금하지 않는다
        // (cross-process race 방어) — 그 잠금은 cooldownUntil이 없어 자정까지 해제 경로가 없다.
        if CooldownMonitor.shouldReshieldOnOverrideExhaustion(
            isCooldownRule: SharedStore.resolvedGroup(id: groupID)?.ruleKind == .cooldown,
            isInCooldown: SharedStore.isInCooldown(groupID)
        ) {
            SharedStore.markGroupShielded(groupID)
        } else {
            GTLog.override.notice("재잠금 스킵(휴식 이미 재충전됨) \(self.groupLabel(groupID), privacy: .public)")
        }
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
        // 오늘 규칙 기준으로 예산/휴식을 판정한다(요일별 그룹은 오늘 쿨다운 파라미터로 투영).
        guard let group = SharedStore.resolvedGroup(id: groupID) else { return }
        // 오늘 규칙이 쿨다운이 아니면 stale tick으로 간주하고 무시한다 — 어제 측정창의 자정
        // 재무장(undocumented)으로 stale cdtick이 도착하면 '제한 없음' 요일에 startCooldown +
        // 잠금이 걸릴 수 있다(요일 전환 심층 방어, daily tick 게이트와 동일).
        guard group.ruleKind == .cooldown else {
            GTLog.cooldown.notice(
                "stale cooldown tick 무시(오늘 규칙 불일치) \(self.groupLabel(groupID), privacy: .public)"
            )
            return
        }
        // tick 분은 cooldown baseline(등록 시점 usedTime) 기준 상대값이므로
        // 사이클 전체 사용량으로 복원해 올린다(역행 방지).
        let baseline = SharedStore.cooldownBaselineByGroupID[groupID] ?? 0
        let used = SharedStore.raiseUsedTime(
            to: CooldownMonitor.absoluteUsedMinutes(baseline: baseline, tickMinute: minute),
            for: groupID
        )
        GTLog.cooldown.notice(
            "예산 사용 측정 \(self.groupLabel(groupID), privacy: .public) used=\(used, privacy: .public)/\(group.cooldownUsageMinutes, privacy: .public)m"
        )

        // 이미 휴식 중이거나 결제(override) 중이면 잠금 트리거를 건너뛴다(진행만 갱신).
        guard !SharedStore.isInCooldown(groupID),
              !SharedStore.usageBasedOverrideGroupIDs.contains(groupID) else { return }
        // 예산 소진 잠금 전에 50·90% 임박 알림(남은 분 = 예산 - 사용량).
        emitUsageAlerts(groupID: groupID, used: used, limit: group.cooldownUsageMinutes, kind: .cooldown)
        // 아직 예산이 남았으면 진행바만 갱신하고 끝.
        guard used >= group.cooldownUsageMinutes else { return }

        let now = Date()
        let until = CooldownMonitor.cooldownEnd(now: now, durationMinutes: group.cooldownDurationMinutes)
        GTLog.cooldown.notice(
            "예산 소진 → 휴식 진입 \(self.groupLabel(groupID), privacy: .public) until=\(until, privacy: .public) duration=\(group.cooldownDurationMinutes, privacy: .public)m"
        )
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
            GTLog.cooldown.error(
                "휴식 타이머 등록 실패 \(self.groupLabel(groupID), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
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
            GTLog.cooldown.notice("재충전 스킵(이미 휴식 해제됨) \(self.groupLabel(groupID), privacy: .public)")
            applyShieldFromGroups()
            return
        }
        guard CooldownMonitor.shouldRechargeOnTimerEnd(
            cooldownEnd: SharedStore.cooldownEnd(for: groupID),
            now: Date()
        ) else {
            GTLog.cooldown.notice("재충전 스킵(종료 예정 미래 → 휴식 보존) \(self.groupLabel(groupID), privacy: .public)")
            applyShieldFromGroups()
            return
        }
        let generation = SharedStore.endCooldownAndRecharge(for: groupID)
        // 휴식 종료 = 다시 사용 가능. 자정 리셋(handleHeartbeat)이 아닌 정상 타이머 종료 경로에서만 알린다.
        NotificationService.scheduleRechargeAvailable(
            groupName: SharedStore.group(id: groupID)?.displayName ?? ""
        )
        let center = DeviceActivityCenter()
        // 직전 사이클의 사용 예산 activity를 멈춘 뒤 새 generation으로 재등록. 살아남은 연장
        // (override) 모니터도 함께 멈춰, 연장분을 다 쓰기 전 휴식이 종료된 경우에도 재충전 후
        // 소진 tick이 오지 않게 한다(미등록 activity stop은 no-op라 무해).
        center.stopMonitoring([
            .cooldownUsage(for: groupID, generation: generation - 1),
            .override(for: groupID),
        ])
        // 오늘 규칙 기준으로 재등록한다(요일별 그룹은 오늘 쿨다운 예산으로 투영). 오늘이 쿨다운이 아니면
        // 예산/규칙이 맞지 않아 재등록하지 않고, 다음 sync·자정 재무장이 오늘 규칙으로 다시 잡는다.
        if let group = SharedStore.resolvedGroup(id: groupID),
           group.ruleKind == .cooldown, group.cooldownUsageMinutes > 0 {
            do {
                try CooldownMonitor.startUsageMonitoring(
                    center: center,
                    group: group,
                    generation: generation
                )
                GTLog.cooldown.notice(
                    "휴식 종료 → 재충전 완료 \(self.groupLabel(groupID), privacy: .public) gen=\(generation, privacy: .public)"
                )
            } catch {
                GTLog.cooldown.error(
                    "재충전 등록 실패 \(self.groupLabel(groupID), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
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

    /// 한도 임박(50·90%) 알림 발송. daily/cooldown은 절대 사용량·한도를, override는 연장 내 누적 분·
    /// granted를 넘긴다. 등록된 threshold 틱 배열의 인덱스로 단계를 정하고(`UsageAlertPolicy.ticks`),
    /// 그룹/연장 사이클별 중복방지 Set으로 단계당 한 번만 보낸다. used가 단계 minute을 넘긴 미발송
    /// 단계를 모두 발송한다(빠르게 써서 50%를 건너뛰면 같은 tick에서 50·90%가 함께 나갈 수 있다).
    private func emitUsageAlerts(groupID: UUID, used: Int, limit: Int, kind: UsageAlertKind) {
        guard SharedStore.isUsageAlertEnabled, limit > 0 else { return }
        let alerts = UsageAlertPolicy.ticks(DailyMonitor.dailyThresholdMinutes(limit: limit))
        guard !alerts.isEmpty else { return }
        let name = SharedStore.group(id: groupID)?.displayName ?? ""
        let remaining = max(0, limit - used)
        for alert in alerts where used >= alert.minute {
            // 연장은 별도 사이클(연장 시작·종료에서 리셋)이라 override용 Set으로, 그 외는 일일/쿨다운 Set으로 관리.
            let claimed = kind == .override
                ? SharedStore.claimOverrideAlert(percent: alert.percent, for: groupID)
                : SharedStore.claimUsageAlert(percent: alert.percent, for: groupID)
            guard claimed else { continue }
            GTLog.activity.notice(
                "사용량 알림 발송 \(self.groupLabel(groupID), privacy: .public) percent=\(alert.percent, privacy: .public) remain=\(remaining, privacy: .public)m override=\(kind == .override, privacy: .public)"
            )
            NotificationService.scheduleUsageAlert(
                groupName: name,
                kind: kind,
                percent: alert.percent,
                remainingMinutes: remaining
            )
        }
    }

    @discardableResult
    private func applyShieldFromGroups() -> Int {
        // 금고 전역 설정(denyAppRemoval·자동 날짜) 재평가. 만료는 lazy 판정이라 별도 해제
        // 트리거가 없다 — 자정 하트비트·틱·시간대 콜백이 전부 이 함수를 지나므로, 여기서
        // 재평가하면 자정 만료 해제가 extension 단독으로도 이뤄진다(리셋 지점 개별 삽입보다 견고).
        StrictLockEnforcement.apply(to: store)

        let applicationTokens = SharedStore.shieldApplicationTokens()
        let webDomainTokens = SharedStore.shieldWebDomainTokens()
        let tokenCount = applicationTokens.count + webDomainTokens.count
        let lockedCount = SharedStore.shieldedGroupIDs.count
        guard tokenCount > 0 else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            SharedStore.isShieldActive = false
            GTLog.shield.notice("Shield 해제(잠긴 그룹 없음) lockedGroups=\(lockedCount, privacy: .public)")
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
        // 토큰 값은 opaque/민감이라 로깅하지 않고 개수만 남긴다.
        GTLog.shield.notice(
            "Shield 적용 lockedGroups=\(lockedCount, privacy: .public) apps=\(applicationTokens.count, privacy: .public) webs=\(webDomainTokens.count, privacy: .public)"
        )
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
