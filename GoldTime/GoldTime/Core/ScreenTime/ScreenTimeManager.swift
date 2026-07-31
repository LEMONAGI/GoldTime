//
//  ScreenTimeManager.swift
//  GoldTime
//
//  DeviceActivityCenter 기반 자동 모니터링 동기화, 쉴드 적용/해제, 연장 처리.
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import os

// daily/dailyGroup/dailyGroupID/dailyHeartbeat/override 및 DeviceActivityEvent.Name.tick/tickInfo는
// DailyMonitor.swift로 이동(앱·extension 공유 단일 출처). window.*/timeWindow(for:index:)/
// timeWindowGroupID/maxTimeWindowsPerGroup/시간대 등록은 TimeWindowMonitor.swift로 이동. 여기서
// 다시 선언하지 말 것.
extension DeviceActivityEvent.Name {
    /// 광고/1분 연장 중 사용량 추적 1회성 이벤트. `usageTick.<gid>.<minute>` 형식으로
    /// override 시작 시점부터 누적 minute분 사용 시 한 번 발화한다 (relay 없음).
    nonisolated static func usageTick(for groupID: UUID, minute: Int) -> Self {
        Self("usageTick.\(groupID.uuidString).\(minute)")
    }

    /// `usageTick.<gid>.<minute>`에서 (groupID, minute) 추출.
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

protocol OverrideMonitorRegistering {
    func stopMonitoring(_ activities: [DeviceActivityName])
    func startMonitoring(
        _ activity: DeviceActivityName,
        during schedule: DeviceActivitySchedule,
        events: [DeviceActivityEvent.Name: DeviceActivityEvent]
    ) throws
}

struct DeviceActivityOverrideMonitorRegistrar: OverrideMonitorRegistering {
    func stopMonitoring(_ activities: [DeviceActivityName]) {
        DeviceActivityCenter().stopMonitoring(activities)
    }

    func startMonitoring(
        _ activity: DeviceActivityName,
        during schedule: DeviceActivitySchedule,
        events: [DeviceActivityEvent.Name: DeviceActivityEvent]
    ) throws {
        try DeviceActivityCenter().startMonitoring(activity, during: schedule, events: events)
    }
}

enum ScreenTimeManager {
    enum ManagerError: LocalizedError {
        case invalidConfiguration(String)

        var errorDescription: String? {
            switch self {
            case .invalidConfiguration(let message):
                return message
            }
        }
    }

    enum ExtensionSource: Equatable {
        case oneMinute
        case adReward
    }

    enum ExtensionFailure: Error, Equatable {
        case groupNotFound
        case oneMinuteLimitReached
        case relockTimerRegistrationFailed
    }

    struct GroupExtensionResult {
        let group: SharedStore.ScreenTimeGroup
        let durationSeconds: Int
        let overrideUntil: Date
        let remainingLockedGroups: [SharedStore.ScreenTimeGroup]
    }

    private static var center: DeviceActivityCenter { DeviceActivityCenter() }
    private static var store: ManagedSettingsStore { ManagedSettingsStore(named: .goldtime) }
    static var overrideMonitorRegistrar: any OverrideMonitorRegistering = DeviceActivityOverrideMonitorRegistrar()

    // MARK: - 일일 모니터링 동기화

    // dailySchedule(repeats:true)는 제거됨 — 자정 콜백은 DailyMonitor.dailyHeartbeat가 담당.
    // freshDailyWindow/dailyThresholdMinutes는 DailyMonitor.swift로 이동(앱·extension 공유 단일 출처).

    /// override 측정창(now ~ 당일 23:59:59)이 DeviceActivity 최소(15분) 미만인지. = 23:45부터 true.
    /// true면 `startMonitoring`이 intervalTooShort로 실패하므로 모니터 없는 시간기반 fallback을 쓴다.
    nonisolated static func overrideWindowTooShort(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) else {
            return false
        }
        return endOfDay.timeIntervalSince(now) < 15 * 60
    }

    /// 자정 근처 안내 문구를 보여줄 구간인지. = 자정까지 < 30분, 즉 23:30부터 true.
    /// 행동 변화(23:45) 전에 미리 알려, 23:44에 연장 시작 후 광고 중 23:45를 넘겨도 당황하지 않게 한다.
    nonisolated static func withinNearMidnightNoticeWindow(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) else {
            return false
        }
        return endOfDay.timeIntervalSince(now) < 30 * 60
    }

    static func syncDailyMonitoring(groups: [SharedStore.ScreenTimeGroup], now: Date = Date()) throws {
        resetDailyProtectionStateIfNeeded()

        let sanitizedGroups = sanitized(groups)
        // validGroups는 "오늘의 규칙"으로 투영한 사본(요일별 그룹은 resolved(on:now)로 오늘 규칙만 남고
        // weekdayRules가 스트립된다). persist(:screenTimeGroups)는 아래에서 원본 sanitizedGroups로 하고,
        // 투영본은 등록/판정/churn 비교 전용이다(Core/CLAUDE.md 투영 규율).
        let validGroups = validDailyMonitoringGroups(from: sanitizedGroups, now: now)
        let validGroupIDs = Set(validGroups.map(\.id))

        // 오늘 '제한 없음' 요일 그룹: 투영 ruleKind가 nil이라 validGroups에서 빠진다. 어제의 잠금/연장
        // 잔재를 명시적으로 청소해 오늘은 앱이 열려 있게 한다(override activity stop은 아래 activitiesToStop).
        let unrestrictedTodayIDs = Set(
            sanitizedGroups.filter { $0.isApplied && $0.isUnrestricted(on: now) }.map(\.id)
        )
        // 요일별 모드 여부는 원본에서만 알 수 있다(투영본은 weekdayRules가 스트립됨).
        let appliedWeekdayGroupIDs = Set(
            sanitizedGroups.filter { $0.isApplied && $0.usesWeekdayRules }.map(\.id)
        )

        let staleOverrideActivities = SharedStore.overrideUntilByGroupID.keys
            .filter { !validGroupIDs.contains($0) }
            .map(DeviceActivityName.override(for:))
        let registeredGroupIDs: Set<UUID> = SharedStore.lastRegisteredGroupsByID
            .map { Set($0.keys) } ?? []
        let lastRegistered = SharedStore.lastRegisteredGroupsByID ?? [:]
        var generationByID = SharedStore.lastRegisteredGenerationByID

        // 이번 동기화에서 daily/시간대/쿨다운 경로로 등록할 유효 그룹을 각각 분리한다.
        let validDailyGroups = validGroups.filter { $0.ruleKind == .dailyLimit }
        let validWindowGroupIDs = Set(validGroups.filter { $0.ruleKind == .timeWindows }.map(\.id))
        let validCooldownGroupIDs = Set(validGroups.filter { $0.ruleKind == .cooldown }.map(\.id))

        // 삭제/무효화/dailyLimit 전환된 그룹의 stale daily activity 정리.
        // (이전에 daily로 등록됐다가 timeWindows로 바뀐 그룹의 daily activity도 여기서 멈춘다)
        let staleDailyGroupIDs = registeredGroupIDs
            .subtracting(Set(validDailyGroups.map(\.id)))
        let staleGroupActivities = staleDailyGroupIDs
            .map { groupID -> DeviceActivityName in
                .dailyGroup(for: groupID, generation: generationByID[groupID] ?? 0)
            }

        // 시간대 그룹이 변경됐거나(또는 dailyLimit/삭제로 무효화됐거나) 새로 들어온 경우,
        // 해당 그룹의 window activity 슬롯을 전부 멈췄다가 필요 시 아래에서 다시 등록한다.
        // appliedWeekdayGroupIDs를 합집합에 더하는 이유: 자정 리셋이 lastRegisteredGroupsByID를 비워
        // previousWindowGroupIDs가 빈 상태에서, "어제 timeWindows → 오늘 다른 규칙" 요일 그룹의
        // repeats:true window activity가 영원히 발화하는 누수를 차단한다. 무변경 유효 window 그룹은
        // 아래 내부 가드가 stop을 막고, 미등록 activity stop은 no-op라 무해하다.
        let previousWindowGroupIDs = Set(lastRegistered.filter { $0.value.ruleKind == .timeWindows }.map(\.key))
        let windowGroupIDsToResetMonitoring = previousWindowGroupIDs
            .union(validWindowGroupIDs)
            .union(appliedWeekdayGroupIDs)
        let staleWindowActivities = windowGroupIDsToResetMonitoring.flatMap { groupID -> [DeviceActivityName] in
            // 변경되지 않은 시간대 그룹은 재등록을 피해야 하므로 stop도 하지 않는다.
            if validWindowGroupIDs.contains(groupID),
               lastRegistered[groupID] == validGroups.first(where: { $0.id == groupID }) {
                return []
            }
            return TimeWindowMonitor.allWindowActivities(for: groupID)
        }

        // 쿨다운 그룹이 변경/무효화/삭제됐거나 새로 들어온 경우, 사용 예산·휴식 타이머 activity를
        // 멈췄다가 필요 시 아래에서 다시 등록한다(변경 없는 쿨다운 그룹은 건드리지 않음).
        let previousCooldownGroupIDs = Set(lastRegistered.filter { $0.value.ruleKind == .cooldown }.map(\.key))
        let cooldownGroupIDsToResetMonitoring = previousCooldownGroupIDs.union(validCooldownGroupIDs)
        let staleCooldownActivities = cooldownGroupIDsToResetMonitoring.flatMap { groupID -> [DeviceActivityName] in
            let isStillCooldown = validCooldownGroupIDs.contains(groupID)
            let isUnchanged = lastRegistered[groupID] == validGroups.first(where: { $0.id == groupID })
            return cooldownActivitiesToStop(
                groupID: groupID,
                generation: SharedStore.cooldownGenerationByID[groupID] ?? 0,
                isStillCooldown: isStillCooldown,
                isUnchanged: isUnchanged,
                isInCooldownRest: SharedStore.isInCooldown(groupID, now: now)
            )
        }

        // persist는 반드시 원본 sanitizedGroups(투영본 절대 금지 — weekdayRules 소실).
        SharedStore.screenTimeGroups = sanitizedGroups
        // 오늘 '제한 없음' 그룹의 override activity도 함께 멈춘다(no-op 무해). shield/override 메타는 아래
        // 명시 청소 + pruneShieldState가 정리한다.
        let unrestrictedOverrideActivities = unrestrictedTodayIDs.map(DeviceActivityName.override(for:))
        let activitiesToStop = staleOverrideActivities + staleGroupActivities + staleWindowActivities + staleCooldownActivities + unrestrictedOverrideActivities
        if !activitiesToStop.isEmpty {
            center.stopMonitoring(activitiesToStop)
        }
        // 요일 그룹의 daily gen은 오늘 무효(제한 없음 등)여도 보존한다 — 비daily 요일을 지나도
        // 이름 연속성이 유지돼야 과거 stop된 daily activity 이름 재사용(카운터 승계 회귀)을 막는다.
        for staleID in registeredGroupIDs.subtracting(validGroupIDs).subtracting(appliedWeekdayGroupIDs) {
            generationByID.removeValue(forKey: staleID)
        }

        // 오늘 '제한 없음'인 요일 그룹: 어제 잠금·연장 잔재를 명시적으로 청소한다.
        for groupID in unrestrictedTodayIDs {
            SharedStore.unmarkGroupShielded(groupID)
            SharedStore.clearOverride(for: groupID)
        }

        // pruneShieldState 이원화: shield/override/cooldownUntil은 오늘 유효 그룹 기준으로 prune하되,
        // cooldownGeneration·baseline은 "존재하는 그룹 전체" 기준으로 보존한다(삭제 그룹만 prune).
        // 오늘 '제한 없음'인 요일 그룹의 cooldown generation이 지워지면 다음 등록이 gen 0을 재사용해
        // stop된 cooldownUsage activity 이름을 재사용 → 카운터 승계로 1분 만에 잠기는 회귀가 재발한다.
        let existingGroupIDs = Set(sanitizedGroups.map(\.id))
        SharedStore.pruneShieldState(
            keepingGroupIDs: validGroupIDs,
            keepingCooldownProgressGroupIDs: existingGroupIDs
        )

        // 쿨다운→다른 규칙으로 전환된(삭제 아님) 그룹: 좀비 휴식 상태를 정리한다.
        // pruneShieldState는 삭제 그룹만 정리하므로 규칙 전환은 여기서 처리해야 한다. 휴식 플래그
        // (cooldownUntil)가 남으면 다시 쿨다운으로 돌아올 때 cooldownEditAction이 .keepCooldownRest로
        // 빠지고 registerCooldownGroup이 early-return해 어떤 모니터도 등록되지 않는다(측정·재잠금 불가).
        // generation도 올라가 위에서 stop한 cooldownUsage activity 이름 재사용(즉시 발화 회귀)을 막는다.
        // 오늘 '제한 없음'으로 넘어간 요일 그룹도 valid에서 빠지므로, 교집합 기준을
        // validGroupIDs ∪ unrestrictedTodayIDs로 확장해 좀비 휴식 플래그를 정리한다.
        let cooldownRuleLeavers = previousCooldownGroupIDs
            .intersection(validGroupIDs.union(unrestrictedTodayIDs))
            .subtracting(validCooldownGroupIDs)
        for groupID in cooldownRuleLeavers {
            SharedStore.clearCooldownCycle(for: groupID)
        }

        // 전체 해체는 유효 그룹이 0이고 적용된 요일 그룹도 없을 때만. 요일 그룹이 있으면(주말 전 그룹
        // '제한 없음'이어도) 하트비트·isDailyMonitoringEnabled를 살려 다음날 자정 재무장이 가능하게
        // 아래 일반 경로로 계속 진행한다(빈 validGroups는 아래 루프·applyShield가 안전하게 처리).
        let hasAppliedWeekdayGroups = !appliedWeekdayGroupIDs.isEmpty
        if validGroups.isEmpty && !hasAppliedWeekdayGroups {
            center.stopMonitoring()
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            SharedStore.isDailyMonitoringEnabled = false
            SharedStore.clearAllShieldState()
            SharedStore.lastRegisteredGenerationByID = [:]
            return
        }

        // 그룹별 변경 감지: 변경된 그룹만 재시작 (usedTime은 SharedStore에 보존).
        // validGroups·lastRegistered 양쪽 모두 투영본이라, churn 가드 `last != group`은 "저장된 오늘
        // 투영본 vs 오늘 투영본" 비교다 → 다른 요일 규칙만 편집하면 오늘 모니터가 재시작되지 않는다.
        var newRegistered = lastRegistered.filter { validGroupIDs.contains($0.key) }
        var firstError: Error?

        // 자정 하트비트는 오늘 daily/cooldown 유효 그룹 또는 적용된 요일 그룹이 있을 때 등록한다(자정
        // 재무장의 주 경로). 시간대-only 구성은 window가 repeats:true라 불필요하고, 시간대 그룹은
        // window+override로 그룹당 최대 4개 activity를 쓸 수 있어(5그룹×4=20) 하트비트를 더하면 동시
        // 모니터링 상한을 넘길 수 있으므로 등록하지 않는다(DailyMonitor.needsHeartbeat 참조). 요일 그룹은
        // 오늘 전부 '제한 없음'이어도 다음날 자정 재무장을 위해 하트비트를 유지한다. 등록 실패는 이
        // 변경의 핵심 경로가 사라지는 것이므로 try?로 삼키지 않고 firstError로 전파한다(관측 가능).
        if DailyMonitor.needsHeartbeat(for: validGroups, appliedGroups: sanitizedGroups) {
            do {
                try center.startMonitoring(.dailyHeartbeat, during: DailyMonitor.heartbeatSchedule, events: [:])
            } catch {
                firstError = firstError ?? error
            }
        } else {
            // 시간대-only(또는 daily/cooldown 없음) → 하트비트 불필요. 이전에 등록됐다면 멈춘다.
            center.stopMonitoring([.dailyHeartbeat])
        }

        for group in validGroups {
            let last = lastRegistered[group.id]
            guard last != group else { continue }

            // 시간대 차단 그룹: daily tick/baseline/generation 경로를 건너뛰고 window activity로 등록.
            // (stale window activity는 위에서 이미 stop했다. group은 오늘 투영본이므로 newRegistered에
            //  기록되는 값도 자연히 투영본이 되어 churn 비교가 오늘 규칙 기준으로 성립한다.)
            if group.ruleKind == .timeWindows {
                // 요일 그룹의 daily gen은 보존한다(오늘만 시간대일 뿐 — 이름 연속성 유지).
                if !appliedWeekdayGroupIDs.contains(group.id) {
                    generationByID.removeValue(forKey: group.id)
                }
                do {
                    try TimeWindowMonitor.startWindowMonitoring(center: center, group: group)
                    newRegistered[group.id] = group
                } catch {
                    firstError = firstError ?? error
                    newRegistered.removeValue(forKey: group.id)   // 등록 실패 = 미추적, stale 표시 방지
                }
                continue
            }

            // 쿨다운 그룹: daily tick/generation 경로를 건너뛰고 사용 예산 모니터로 등록한다.
            // (stale 사용 예산/휴식 타이머 activity는 위에서 이미 stop했다)
            if group.ruleKind == .cooldown {
                // 요일 그룹의 daily gen은 보존한다(오늘만 쿨다운일 뿐 — 이름 연속성 유지).
                if !appliedWeekdayGroupIDs.contains(group.id) {
                    generationByID.removeValue(forKey: group.id)
                }
                let used = SharedStore.usedTimeByGroupID[group.id] ?? 0
                let action = cooldownEditAction(
                    isInCooldown: SharedStore.isInCooldown(group.id, now: now),
                    usedMinutes: used,
                    budgetMinutes: group.cooldownUsageMinutes,
                    nearMidnight: overrideWindowTooShort(now: now)
                )
                switch action {
                case .enterCooldownRest:
                    // 평소 예산 소진 편집 → 즉시 휴식 진입(cdtick 잠금과 동일, 휴식 후 재충전).
                    enterCooldownRest(group, now: now)
                    newRegistered[group.id] = group
                case .lockUntilMidnight:
                    // 자정 직전 예산 소진 → 타이머 없이 잠금만(자정 리셋이 해제·재충전).
                    SharedStore.markGroupShielded(group.id)
                    newRegistered.removeValue(forKey: group.id)   // 자정 후 fresh 재등록 보장
                case .skipUntracked:
                    // 자정 직전 + 예산 남음 → 사용 예산 모니터 등록 불가 → 미추적, 자정 후 재등록.
                    SharedStore.unmarkGroupShielded(group.id)
                    newRegistered.removeValue(forKey: group.id)
                case .registerAvailable:
                    // 일일 한도 잠금 등 기존 shield가 있어도 쿨다운 예산이 남았다면 새 규칙 기준으로
                    // 남은 시간만 측정하며 사용 가능 상태로 전환한다.
                    SharedStore.unmarkGroupShielded(group.id)
                    do {
                        try registerCooldownGroup(group)
                        newRegistered[group.id] = group
                    } catch {
                        firstError = firstError ?? error
                        newRegistered.removeValue(forKey: group.id)   // 등록 실패 = 미추적, stale 표시 방지
                    }
                case .keepCooldownRest:
                    do {
                        try registerCooldownGroup(group)
                        newRegistered[group.id] = group
                    } catch {
                        firstError = firstError ?? error
                        newRegistered.removeValue(forKey: group.id)   // 등록 실패 = 미추적, stale 표시 방지
                    }
                }
                continue
            }

            let currentGen = generationByID[group.id] ?? 0
            let usedMinutes = SharedStore.usedTimeByGroupID[group.id] ?? 0
            let wasLocked = SharedStore.shieldedGroupIDs.contains(group.id)
            let limitChanged = last != nil && last!.dailyLimitMinutes != group.dailyLimitMinutes
            // 이전이 시간대 그룹이었다면(규칙 전환) daily 카운터가 없으므로 항상 재등록한다.
            let ruleChanged = last != nil && last!.ruleKind != group.ruleKind
            let needsMonitoringRestart = last == nil || last!.selection != group.selection || wasLocked || limitChanged || ruleChanged

            if usedMinutes >= group.dailyLimitMinutes {
                center.stopMonitoring([.dailyGroup(for: group.id, generation: currentGen)])
                SharedStore.markGroupShielded(group.id)
                newRegistered[group.id] = group
            } else if needsMonitoringRestart {
                // 같은 activity name으로 재시작하면 DeviceActivity의 schedule-interval 누적 카운터가
                // 그대로 유지되어 1분 만에 잠기는 버그가 발생한다. 새 generation으로 등록해 시스템
                // 카운터를 분리한다.
                center.stopMonitoring([.dailyGroup(for: group.id, generation: currentGen)])
                SharedStore.unmarkGroupShielded(group.id)   // 여기 도달 = usedMinutes < limit → 미잠금
                if overrideWindowTooShort(now: now) {
                    // 자정 직전: freshDailyWindow(now~23:59:59)가 15분 미만이라 startMonitoring이
                    // intervalTooShort로 실패한다. 모니터 등록을 건너뛰고(미추적) 자정 후 첫 sync가
                    // 새로 등록하게 한다. stop한 generation 재사용 금지로 +1 미리 올려둔다.
                    generationByID[group.id] = currentGen + 1
                    newRegistered.removeValue(forKey: group.id)   // last==nil → 자정 후 fresh 재등록
                } else {
                    let nextGen = (last == nil) ? currentGen : currentGen + 1
                    do {
                        try DailyMonitor.startUsageMonitoring(center: center, group: group, generation: nextGen)
                        generationByID[group.id] = nextGen
                        newRegistered[group.id] = group
                    } catch {
                        firstError = firstError ?? error
                        newRegistered.removeValue(forKey: group.id)   // 등록 실패 = 미추적, stale 표시 방지
                    }
                }
            } else {
                // 이름만 변경(selection·한도 동일): DeviceActivity 재시작 없이 등록 정보만 갱신.
                // (한도 변경은 limitChanged로 위 restart 분기에서 baseline 재등록됨)
                SharedStore.unmarkGroupShielded(group.id)
                newRegistered[group.id] = group
            }
        }

        SharedStore.lastRegisteredGroupsByID = newRegistered
        SharedStore.lastRegisteredGenerationByID = generationByID
        SharedStore.isDailyMonitoringEnabled = true
        SharedStore.markStatsTrackingStartedIfNeeded()
        // 시간대 그룹의 '지금 시간대 안인지'를 shieldedGroupIDs에 반영한 뒤 쉴드를 적용한다.
        SharedStore.resyncTimeWindowLocks()
        applyShield()

        // 시간대 차단 5분 전·종료(재사용 가능) 알림을 현재 구성으로 재예약한다(고정 시각이라 캘린더 트리거,
        // DeviceActivity activity를 늘리지 않음). 토글 OFF면 내부에서 기존 예약만 정리한다.
        NotificationService.rescheduleTimeWindowAlerts(groups: groups)

        if let error = firstError { throw error }
    }

    /// 쿨다운 그룹의 사용 예산 모니터를 등록한다. 이미 휴식 중이면 등록하지 않는다(휴식 타이머가
    /// 끝나면 extension이 재충전). 만료된 휴식 상태가 남아 있으면(타이머 놓침) 정리하고 새 사이클로
    /// 충전한다. usage 모니터는 cooldownUsageMinutes분 사용 시 cdtick 이벤트로 잠금을 트리거한다.
    private static func registerCooldownGroup(_ group: SharedStore.ScreenTimeGroup) throws {
        if SharedStore.isInCooldown(group.id) {
            // 휴식 중엔 사용 예산 모니터를 등록하지 않는다(휴식이 끝나야 새 사이클). 단 그 전에
            // 타이머가 실제로 살아 있는지 확인한다 — 전체 stop 경로가 타이머만 지우고 가는 일이 있다.
            restoreCooldownTimerIfNeeded(for: group.id)
            return
        }

        let generation: Int
        if SharedStore.cooldownEnd(for: group.id) != nil {
            // 만료된 휴식 상태가 남아 있음(타이머 놓침) → 정리 + generation 증가 후 새 사이클.
            generation = SharedStore.endCooldownAndRecharge(for: group.id)
            // 다른 두 재충전 경로와 동일하게 살아남은 연장(override) 모니터도 stop한다
            // (슬롯 점유 방지, no-op 무해).
            center.stopMonitoring([.override(for: group.id)])
        } else {
            generation = SharedStore.cooldownGenerationByID[group.id] ?? 0
        }
        try CooldownMonitor.startUsageMonitoring(center: center, group: group, generation: generation)
    }

    /// 휴식 중인데 `cooldownTimer` activity가 사라졌으면 남은 휴식 시간으로 되살린다.
    ///
    /// 전체 stop 경로(스크린타임 권한 철회→재승인, 설정의 "스크린 타임 재연결" =
    /// `reconnectMonitoring`의 `center.stopMonitoring()`)는 타이머까지 지우지만 휴식 상태
    /// (`cooldownUntil`)는 SharedStore에 그대로 남는다. 그 뒤 재등록이 `.keepCooldownRest`로
    /// 들어와 early-return하면 **휴식 종료 콜백이 영영 오지 않아 휴식이 자동으로 안 끝난다**
    /// (2026-07-29 실기기 실측). 복구 조건 판정은 `CooldownMonitor.shouldRestoreCooldownTimer` —
    /// **타이머가 살아 있으면 손대지 않는다**(재등록은 휴식 시작을 리셋한다).
    private static func restoreCooldownTimerIfNeeded(for groupID: UUID, now: Date = Date()) {
        let timer = DeviceActivityName.cooldownTimer(for: groupID)
        guard let until = SharedStore.cooldownEnd(for: groupID),
              CooldownMonitor.shouldRestoreCooldownTimer(
                  cooldownEnd: until,
                  isTimerMonitored: center.activities.contains(timer),
                  now: now
              ) else { return }

        do {
            try CooldownMonitor.startCooldownTimer(center: center, groupID: groupID, until: until, now: now)
            GTLog.cooldown.notice(
                "휴식 타이머 복구 \(groupID.uuidString.prefix(4), privacy: .public) 남은=\(Int(until.timeIntervalSince(now) / 60), privacy: .public)m"
            )
        } catch {
            // 자가치유(foreground)·자정 리셋이 남아 있어 치명적이진 않지만 조용히 삼키지 않는다.
            SharedStore.enqueueScreenTimeError(context: "cooldownTimerRestore", message: "\(error)")
            GTLog.cooldown.error(
                "휴식 타이머 복구 실패 \(groupID.uuidString.prefix(4), privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    /// 쿨다운 그룹을 즉시 휴식 진입시킨다(편집으로 사용 예산이 현재 사용량 이하로 바뀐 경우 등).
    /// extension의 `handleCooldownUsageTick` 잠금부와 동일하게 휴식 타이머까지 등록한다. 단 편집
    /// 트리거 잠금이라 분석 shield_hit은 남기지 않는다(사용 중 막힘이 아니라 설정 변경).
    /// 휴식 종료가 내일로 넘어가면 당일 23:59:59로 잘라 자정 리셋 정책과 맞춘다.
    private static func enterCooldownRest(_ group: SharedStore.ScreenTimeGroup, now: Date) {
        let until = CooldownMonitor.cooldownEnd(now: now, durationMinutes: group.cooldownDurationMinutes)
        SharedStore.startCooldown(until: until, for: group.id)   // 내부에서 markGroupShielded
        try? CooldownMonitor.startCooldownTimer(
            center: center,
            groupID: group.id,
            until: until,
            now: now
        )
    }

    /// 쿨다운 그룹 편집/재동기화 시 어떤 조치를 취할지 결정한다(Apple framework 호출 없는 순수 판정).
    /// daily의 `usedMinutes >= limit → 즉시 잠금`에 대응해, 쿨다운도 예산 소진이면 즉시 잠금한다.
    /// - 휴식 중: `.keepCooldownRest`(registerCooldownGroup이 early-return하므로 무해, 모니터 미등록).
    /// - 예산 소진(`used >= budget`): 평소 `.enterCooldownRest`(휴식 진입+타이머), 자정 직전
    ///   `.lockUntilMidnight`(타이머 자정 넘김 회피 + 자정 리셋이 재충전하므로 markGroupShielded만).
    /// - 예산 남음: 평소 `.registerAvailable`(기존 잠금 해제 후 남은 예산 측정), 자정 직전
    ///   `.skipUntracked`(사용 예산 모니터 등록 불가 → 미추적).
    enum MonitorEditAction: Equatable {
        case registerAvailable
        case keepCooldownRest
        case skipUntracked
        case lockUntilMidnight
        case enterCooldownRest
    }

    nonisolated static func cooldownEditAction(
        isInCooldown: Bool,
        usedMinutes: Int,
        budgetMinutes: Int,
        nearMidnight: Bool
    ) -> MonitorEditAction {
        if isInCooldown { return .keepCooldownRest }
        if usedMinutes >= budgetMinutes {
            return nearMidnight ? .lockUntilMidnight : .enterCooldownRest
        }
        return nearMidnight ? .skipUntracked : .registerAvailable
    }

    /// 재동기화 시 쿨다운 그룹의 어떤 모니터 activity를 멈출지 결정한다(Apple framework 호출 없는 순수 판정).
    /// - 변경 없는 유효 쿨다운 그룹: 아무것도 멈추지 않는다(재등록 churn 방지).
    /// - 휴식 중인 쿨다운 그룹 편집: 현재 휴식을 보존하기 위해 휴식 타이머(`cooldownTimer`)는 멈추지
    ///   않고, 누적 카운터 분리를 위해 stale 사용 예산(`cooldownUsage`) activity만 정리한다. 변경된
    ///   설정은 휴식 종료 후 재충전(`handleCooldownTimerEnded`) 시점부터 적용된다.
    /// - 그 외(삭제/규칙 전환/휴식 아님): 둘 다 멈췄다가 필요 시 새 generation으로 재등록한다.
    nonisolated static func cooldownActivitiesToStop(
        groupID: UUID,
        generation: Int,
        isStillCooldown: Bool,
        isUnchanged: Bool,
        isInCooldownRest: Bool
    ) -> [DeviceActivityName] {
        if isStillCooldown && isUnchanged { return [] }
        if isStillCooldown && isInCooldownRest {
            return [.cooldownUsage(for: groupID, generation: generation)]
        }
        return [.cooldownUsage(for: groupID, generation: generation),
                .cooldownTimer(for: groupID)]
    }

    /// now의 유효 모니터링 대상 그룹을 "오늘의 규칙"으로 투영해 반환한다. 요일별 그룹은
    /// resolved(on:now)로 오늘 규칙만 남고(weekdayRules 스트립), 오늘 '제한 없음'이면 ruleKind가 nil이
    /// 되어 기존 정책이 자연 제외한다. 비요일 그룹은 self 그대로 통과한다.
    static func validDailyMonitoringGroups(
        from groups: [SharedStore.ScreenTimeGroup],
        now: Date = Date()
    ) -> [SharedStore.ScreenTimeGroup] {
        sanitized(groups).map { $0.resolved(on: now) }.filter { group in
            ScreenTimeGroupPolicy.invalidReason(for: group.policySnapshot) == nil
        }
    }

    static func reconnectMonitoring() throws {
        // stopMonitoring()은 override activity도 함께 멈춘다. 사용량 기반 override 메타데이터를
        // 보존하면 해당 그룹이 Shield union에서 계속 제외되어 재잠금될 수 없다.
        SharedStore.clearAllOverrideState()
        center.stopMonitoring()
        SharedStore.lastRegisteredGroupsByID = nil
        SharedStore.lastRegisteredGenerationByID = [:]
        try syncDailyMonitoring(groups: SharedStore.screenTimeGroups)
    }

    @discardableResult
    private static func resetDailyProtectionStateIfNeeded(now: Date = Date()) -> Bool {
        guard SharedStore.resetDailyProtectionStateIfNeeded(now: now) else {
            return false
        }

        clearShield()
        return true
    }

    private static func sanitized(
        _ groups: [SharedStore.ScreenTimeGroup]
    ) -> [SharedStore.ScreenTimeGroup] {
        Array(groups.prefix(SharedStore.maxGroupCount)).map { group in
            var sanitized = group
            sanitized.selection = group.selection.supportedTokenSelection
            return sanitized
        }
    }

    // daily 그룹 등록(registerGroup)은 DailyMonitor.startUsageMonitoring으로 이동(앱·extension 공유).

    // MARK: - 쉴드 제어

    static func applyShield() {
        let applicationTokens = SharedStore.shieldApplicationTokens()
        let webDomainTokens = SharedStore.shieldWebDomainTokens()
        guard !applicationTokens.isEmpty || !webDomainTokens.isEmpty else {
            clearShield()
            return
        }

        store.shield.applications = applicationTokens.isEmpty ? nil : applicationTokens
        store.shield.applicationCategories = nil
        store.shield.webDomains = webDomainTokens.isEmpty ? nil : webDomainTokens
        SharedStore.isShieldActive = true
        // 토큰 값은 opaque/민감이라 개수만 로깅한다.
        GTLog.shield.notice(
            "Shield 적용(앱) lockedGroups=\(SharedStore.shieldedGroupIDs.count, privacy: .public) apps=\(applicationTokens.count, privacy: .public) webs=\(webDomainTokens.count, privacy: .public)"
        )
    }

    static func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        SharedStore.isShieldActive = false
        GTLog.shield.notice("Shield 해제(앱)")
    }

    /// 특정 그룹의 쉴드를 해제하고 사용량 기반으로 재잠금한다.
    /// 그 그룹의 앱을 누적 N분(=seconds/60) 사용하면 즉시 다시 잠긴다.
    /// 시간이 흘러도 사용하지 않으면 잠기지 않는다 (자정 daily reset 때까지 유지).
    @discardableResult
    static func releaseShield(
        forSeconds seconds: TimeInterval,
        groupID: UUID,
        now: Date = Date()
    ) -> Result<Date, ExtensionFailure> {
        guard let group = SharedStore.group(id: groupID) else {
            return .failure(.groupNotFound)
        }

        let minutes = max(1, Int((seconds / 60.0).rounded(.up)))
        let end = now.addingTimeInterval(seconds)

        // override 시작 시점부터 사용량을 측정하기 위해 "지금"부터 시작하는 새 스케줄을 쓴다.
        // dailySchedule(자정 시작)을 쓰면 이미 누적된 사용량 때문에 threshold가 즉시 충족돼
        // relay가 연쇄 발화(runaway)하므로, daily와 동일하게 최대 10개의 1회성 이벤트를 한 번에 등록한다.
        // 각 이벤트는 딱 한 번만 발화하므로 재등록(relay)이 없어 폭주가 구조적으로 불가능하다.
        // 분배 마지막 원소가 항상 minutes(=granted)라 마지막 이벤트에서 정확히 재잠금된다.
        //
        // 측정창은 반드시 date-less(`[.hour,.minute,.second]`, end 23:59:59)여야 한다.
        // intervalEnd에 `.day`/절대 날짜 컴포넌트를 넣으면 iOS가 threshold를 즉시·배치 발화시켜
        // 연장 직후 m=2,3,4,…가 한꺼번에 터진다(Apple Forums 확인, 회귀 204a691). freshDailyWindow와 동일 형태.
        let calendar = Calendar.current

        // 자정 직전(측정창 < 15분, 23:45부터)엔 DeviceActivity 최소 제약 때문에 startMonitoring이
        // intervalTooShort로 실패한다(Apple Forums 확인). 모니터를 포기하고 "자정까지" 시간기반
        // override로 해제한다. grant와 무관하게 23:59:59까지 풀어주고(보너스), 재잠금은
        // reapplyShieldIfOverrideExpired(foreground) + 자정 daily 리셋이 보장한다.
        // usageBasedOverride로 표시하지 않아야 clearExpiredOverrides가 시간 만료로 정리할 수 있다.
        if overrideWindowTooShort(now: now) {
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? end
            let activity = DeviceActivityName.override(for: groupID)
            overrideMonitorRegistrar.stopMonitoring([activity])
            SharedStore.setOverride(until: endOfDay, for: groupID)
            GTLog.override.notice(
                "연장 해제(자정 직전 시간기반 fallback) group=\(group.name, privacy: .public)#\(groupID.uuidString.prefix(4), privacy: .public) until=23:59:59 (모니터 미등록)"
            )
            applyShield()
            SharedStore.recordOverrideRegistration(
                activityName: activity.rawValue,
                groupID: groupID,
                overrideUntil: endOfDay,
                registeredAt: now,
                message: "near-midnight time-based override (until 23:59:59, no monitor)"
            )
            return .success(endOfDay)
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.hour, .minute, .second], from: now),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: false
        )
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for m in DailyMonitor.dailyThresholdMinutes(limit: minutes, maxEvents: 10) {
            events[.usageTick(for: groupID, minute: m)] = DeviceActivityEvent(
                applications: group.selection.applicationTokens,
                categories: [],
                webDomains: group.selection.webDomainTokens,
                threshold: DateComponents(minute: m)
            )
        }
        let activity = DeviceActivityName.override(for: groupID)
        overrideMonitorRegistrar.stopMonitoring([activity])
        do {
            try overrideMonitorRegistrar.startMonitoring(
                activity,
                during: schedule,
                events: events
            )
            SharedStore.setOverride(until: end, for: groupID)
            SharedStore.markUsageBasedOverride(groupID)
            SharedStore.recordOverrideBaseline(
                groupID: groupID,
                baseline: SharedStore.usedTimeByGroupID[groupID] ?? 0,
                grantedMinutes: minutes
            )
            applyShield()
            GTLog.override.notice(
                "연장 해제 등록 성공(사용량 기반) group=\(group.name, privacy: .public)#\(groupID.uuidString.prefix(4), privacy: .public) granted=\(minutes, privacy: .public)m until=\(end, privacy: .public)"
            )
            SharedStore.recordOverrideRegistration(
                activityName: activity.rawValue,
                groupID: groupID,
                overrideUntil: end,
                registeredAt: now,
                message: "registered usage-based override monitor (\(minutes)m)"
            )
        } catch {
            GTLog.override.error(
                "연장 해제 등록 실패 group=\(group.name, privacy: .public)#\(groupID.uuidString.prefix(4), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            SharedStore.recordOverrideRegistration(
                activityName: activity.rawValue,
                groupID: groupID,
                overrideUntil: end,
                registeredAt: now,
                message: "failed to register override monitor: \(error.localizedDescription)"
            )
            SharedStore.enqueueScreenTimeError(
                context: "overrideMonitor",
                message: error.localizedDescription
            )
            return .failure(.relockTimerRegistrationFailed)
        }

        return .success(end)
    }

    @discardableResult
    static func extendGroup(
        groupID: UUID,
        duration seconds: Int,
        source: ExtensionSource,
        now: Date = Date()
    ) -> Result<GroupExtensionResult, ExtensionFailure> {
        guard let group = SharedStore.group(id: groupID) else {
            return .failure(.groupNotFound)
        }

        if source == .oneMinute {
            rolloverCounterIfNeeded(now: now)
            guard SharedStore.oneMinuteUsedToday < SharedStore.oneMinuteDailyLimit else {
                return .failure(.oneMinuteLimitReached)
            }
        }

        let releaseResult = releaseShield(
            forSeconds: TimeInterval(seconds),
            groupID: groupID,
            now: now
        )

        let overrideUntil: Date
        switch releaseResult {
        case .success(let end):
            overrideUntil = end
        case .failure(let failure):
            return .failure(failure)
        }

        switch source {
        case .oneMinute:
            SharedStore.oneMinuteUsedToday += 1
            SharedStore.recordOneMinuteUnlock(seconds: seconds)
        case .adReward:
            // 통계 시간 = 실제 해제 지속 시간 = overrideUntil - now.
            // 정상 경로는 overrideUntil=now+seconds라 곧 seconds. 자정 직전 fallback은 overrideUntil=자정이라
            // "자정까지 남은 시간"이 그대로 기록된다(23:45→약 15분, 23:55→약 5분). 횟수는 함수 내부에서 항상 +1.
            let usableSeconds = max(0, Int(overrideUntil.timeIntervalSince(now)))
            SharedStore.recordAdUnlock(seconds: usableSeconds)
        }

        return .success(
            GroupExtensionResult(
                group: group,
                durationSeconds: seconds,
                overrideUntil: overrideUntil,
                remainingLockedGroups: SharedStore.lockedGroups(now: now)
            )
        )
    }

    @discardableResult
    static func consumeAdReward(for groupID: UUID) -> Bool {
        if case .success = extendGroup(
            groupID: groupID,
            duration: 15 * 60,
            source: .adReward
        ) {
            return true
        }
        return false
    }

    @discardableResult
    static func reapplyShieldIfOverrideExpired(now: Date = Date()) -> Bool {
        // override 만료뿐 아니라 시간대 진입/이탈, 휴식 종료도 foreground 복귀 시 보정한다.
        let overrideChanged = SharedStore.clearExpiredOverrides(now: now)
        let windowChanged = SharedStore.resyncTimeWindowLocks(now: now).changed
        let cooldownChanged = rechargeExpiredCooldowns(now: now)
        guard overrideChanged || windowChanged || cooldownChanged else {
            return false
        }

        applyShield()
        return SharedStore.isShieldActive
    }

    /// 휴식이 끝났는데 타이머 콜백을 놓친 쿨다운 그룹을 foreground 복귀 시 정리·재충전한다.
    /// (백그라운드에서 앱이 죽어 extension 타이머가 동작하지 못한 경우의 자가 치유 경로)
    @discardableResult
    private static func rechargeExpiredCooldowns(now: Date = Date()) -> Bool {
        let expired = SharedStore.expiredCooldownGroupIDs(now: now)
        guard !expired.isEmpty else { return false }

        for groupID in expired {
            let generation = SharedStore.endCooldownAndRecharge(for: groupID)
            // 정상 타이머 경로(handleCooldownTimerEnded)와 동일하게 직전 사이클의 사용 예산 activity와
            // 휴식 타이머를 함께 멈춘다. cooldownUsage(generation-1)를 남기면 stale activity가 모니터링
            // 슬롯을 잠식하고(반복 자가치유 시 excessiveActivities 위험) 두 재충전 경로가 불일치한다.
            // 살아남은 연장(override) 모니터도 함께 stop해 재충전 후 소진 tick이 오지 않게 한다(no-op 무해).
            center.stopMonitoring([
                .cooldownUsage(for: groupID, generation: generation - 1),
                .cooldownTimer(for: groupID),
                .override(for: groupID),
            ])
            // 오늘 규칙 기준으로 재등록한다(요일별 그룹은 오늘 쿨다운 예산으로 투영). 오늘이 쿨다운이
            // 아니면(요일 전환) 재등록하지 않고 자정 리셋 경로에 맡긴다.
            guard let group = SharedStore.resolvedGroup(id: groupID, now: now),
                  group.ruleKind == .cooldown,
                  group.cooldownUsageMinutes > 0 else { continue }
            if overrideWindowTooShort(now: now) {
                // 자정 직전: usageSchedule(now~23:59:59)이 15분 미만이라 startMonitoring이 intervalTooShort로
                // 실패한다. 등록을 건너뛰고(미추적, syncDailyMonitoring의 .skipUntracked와 동일) 23:59까지 사용
                // 가능하게 두고 자정 리셋이 재충전하게 한다. 의도된 동작이므로 에러로 기록하지 않는다.
                continue
            }
            do {
                try CooldownMonitor.startUsageMonitoring(
                    center: center,
                    group: group,
                    generation: generation
                )
            } catch {
                // 진짜 실패(예: excessiveActivities): 무증상으로 삼키지 않고 기록한다. 그리고 churn 가드를
                // 무효화해 다음 foreground sync가 재등록하게 한다 — 이 경로는 lastRegisteredGroupsByID를
                // 건드리지 않아 last==group이 남고 syncDailyMonitoring(:256)이 그룹을 스킵, 자정 하트비트까지
                // (~최대 24h) 재등록되지 못하기 때문이다. 하트비트 경로의 "성공 시에만 기록" 계약과 동일하게
                // 실패 그룹을 last==nil로 만든다.
                SharedStore.enqueueScreenTimeError(
                    context: "cooldownRecharge",
                    message: error.localizedDescription
                )
                SharedStore.clearRegistration(for: groupID)
            }
        }
        return true
    }

    // MARK: - 1분 카운터

    /// 카운터를 사용하고 1분 연장. 한도 초과 시 false 반환.
    @discardableResult
    static func consumeOneMinute(for groupID: UUID) -> Bool {
        if case .success = extendGroup(
            groupID: groupID,
            duration: 60,
            source: .oneMinute
        ) {
            return true
        }
        return false
    }

    static func rolloverCounterIfNeeded(now: Date = Date()) {
        let calendar = Calendar.current
        if !calendar.isDate(SharedStore.oneMinuteCounterDate, inSameDayAs: now) {
            SharedStore.oneMinuteUsedToday = 0
            SharedStore.oneMinuteCounterDate = now
        }
    }
}

// policySnapshot / policySnapshots 어댑터는 DailyMonitor.swift로 이동(앱·extension 공유).
