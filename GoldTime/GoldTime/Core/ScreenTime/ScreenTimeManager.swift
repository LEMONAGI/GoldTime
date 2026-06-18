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

// daily/dailyGroup/dailyGroupID/dailyHeartbeat 및 DeviceActivityEvent.Name.tick/tickInfo는
// DailyMonitor.swift로 이동(앱·extension 공유 단일 출처). 여기서 다시 선언하지 말 것.
extension DeviceActivityName {
    nonisolated static func override(for groupID: UUID) -> Self {
        Self("override.\(groupID.uuidString)")
    }

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
    /// 한 그룹이 가질 수 있는 시간대 최대 개수(TimeWindowPolicy와 동일). 그룹이 시간대를 줄이거나
    /// dailyLimit으로 바뀌어도 잔여 window activity가 남지 않도록, 정리 시 0...max-1을 전부 stop한다.
    static let maxTimeWindowsPerGroup = 3

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
        let validGroups = validDailyMonitoringGroups(from: sanitizedGroups)
        let validGroupIDs = Set(validGroups.map(\.id))

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
        let previousWindowGroupIDs = Set(lastRegistered.filter { $0.value.ruleKind == .timeWindows }.map(\.key))
        let windowGroupIDsToResetMonitoring = previousWindowGroupIDs.union(validWindowGroupIDs)
        let staleWindowActivities = windowGroupIDsToResetMonitoring.flatMap { groupID -> [DeviceActivityName] in
            // 변경되지 않은 시간대 그룹은 재등록을 피해야 하므로 stop도 하지 않는다.
            if validWindowGroupIDs.contains(groupID),
               lastRegistered[groupID] == validGroups.first(where: { $0.id == groupID }) {
                return []
            }
            return (0..<maxTimeWindowsPerGroup).map { DeviceActivityName.timeWindow(for: groupID, index: $0) }
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

        SharedStore.screenTimeGroups = sanitizedGroups
        let activitiesToStop = staleOverrideActivities + staleGroupActivities + staleWindowActivities + staleCooldownActivities
        if !activitiesToStop.isEmpty {
            center.stopMonitoring(activitiesToStop)
        }
        for staleID in registeredGroupIDs.subtracting(validGroupIDs) {
            generationByID.removeValue(forKey: staleID)
        }
        SharedStore.pruneShieldState(keepingGroupIDs: validGroupIDs)

        // 쿨다운→다른 규칙으로 전환된(삭제 아님) 그룹: 좀비 휴식 상태를 정리한다.
        // pruneShieldState는 삭제 그룹만 정리하므로 규칙 전환은 여기서 처리해야 한다. 휴식 플래그
        // (cooldownUntil)가 남으면 다시 쿨다운으로 돌아올 때 cooldownEditAction이 .keepCooldownRest로
        // 빠지고 registerCooldownGroup이 early-return해 어떤 모니터도 등록되지 않는다(측정·재잠금 불가).
        // generation도 올라가 위에서 stop한 cooldownUsage activity 이름 재사용(즉시 발화 회귀)을 막는다.
        let cooldownRuleLeavers = previousCooldownGroupIDs
            .intersection(validGroupIDs)
            .subtracting(validCooldownGroupIDs)
        for groupID in cooldownRuleLeavers {
            SharedStore.clearCooldownCycle(for: groupID)
        }

        guard !validGroups.isEmpty else {
            center.stopMonitoring()
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            SharedStore.isDailyMonitoringEnabled = false
            SharedStore.clearAllShieldState()
            SharedStore.lastRegisteredGenerationByID = [:]
            return
        }

        // 그룹별 변경 감지: 변경된 그룹만 재시작 (usedTime은 SharedStore에 보존)
        var newRegistered = lastRegistered.filter { validGroupIDs.contains($0.key) }
        var firstError: Error?

        // 자정 하트비트는 daily/cooldown 그룹이 있을 때만 등록한다(자정 재무장의 주 경로).
        // 시간대-only 구성은 window가 repeats:true라 불필요하고, 시간대 그룹은 window+override로
        // 그룹당 최대 4개 activity를 쓸 수 있어(5그룹×4=20) 하트비트를 더하면 동시 모니터링 상한을
        // 넘길 수 있으므로 등록하지 않는다(DailyMonitor.needsHeartbeat 참조). 유효 그룹이 0이면 위
        // 가드의 stopMonitoring()이 하트비트까지 함께 멈춘다. 등록 실패는 이 변경의 핵심 경로가
        // 사라지는 것이므로 try?로 삼키지 않고 firstError로 전파한다(관측 가능).
        if DailyMonitor.needsHeartbeat(for: validGroups) {
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
            // (stale window activity는 위에서 이미 stop했다)
            if group.ruleKind == .timeWindows {
                generationByID.removeValue(forKey: group.id)
                do {
                    try registerTimeWindowGroup(group)
                    newRegistered[group.id] = group
                } catch {
                    firstError = firstError ?? error
                }
                continue
            }

            // 쿨다운 그룹: daily tick/generation 경로를 건너뛰고 사용 예산 모니터로 등록한다.
            // (stale 사용 예산/휴식 타이머 activity는 위에서 이미 stop했다)
            if group.ruleKind == .cooldown {
                generationByID.removeValue(forKey: group.id)
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
                    }
                case .keepCooldownRest:
                    do {
                        try registerCooldownGroup(group)
                        newRegistered[group.id] = group
                    } catch {
                        firstError = firstError ?? error
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

        if let error = firstError { throw error }
    }

    /// 시간대 차단 그룹을 timeWindows 개수만큼 window activity로 등록한다.
    /// TimeWindow의 endMinuteOfDay는 inclusive(차단되는 마지막 분)이므로 스케줄의 intervalEnd는
    /// "차단이 끝나는 순간" = endMinuteOfDay + 1로 변환한다(예: 12:59 차단 → intervalEnd 13:00).
    /// 각 시간대는 repeats:true로 돌고 threshold 이벤트는 없다(잠금은 intervalDidStart에서 resync로,
    /// 해제는 intervalDidEnd에서 resync로 처리).
    private static func registerTimeWindowGroup(_ group: SharedStore.ScreenTimeGroup) throws {
        for (index, window) in group.timeWindows.enumerated() {
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(
                    hour: window.startMinuteOfDay / 60,
                    minute: window.startMinuteOfDay % 60
                ),
                intervalEnd: timeWindowIntervalEnd(forInclusiveEndMinute: window.endMinuteOfDay),
                repeats: true
            )
            try center.startMonitoring(
                .timeWindow(for: group.id, index: index),
                during: schedule,
                events: [:]
            )
        }
    }

    /// inclusive 종료분(E)을 스케줄 intervalEnd(차단 종료 순간 = E+1)로 변환한다.
    /// E가 23:59(1439)면 다음 분이 24:00(DateComponents hour:24 불가)이라 dailySchedule과 동일하게
    /// 23:59:59(하루의 끝)로 표현한다.
    private static func timeWindowIntervalEnd(forInclusiveEndMinute end: Int) -> DateComponents {
        let exclusiveEnd = end + 1
        guard exclusiveEnd < 24 * 60 else {
            return DateComponents(hour: 23, minute: 59, second: 59)
        }
        return DateComponents(hour: exclusiveEnd / 60, minute: exclusiveEnd % 60)
    }

    /// 쿨다운 그룹의 사용 예산 모니터를 등록한다. 이미 휴식 중이면 등록하지 않는다(휴식 타이머가
    /// 끝나면 extension이 재충전). 만료된 휴식 상태가 남아 있으면(타이머 놓침) 정리하고 새 사이클로
    /// 충전한다. usage 모니터는 cooldownUsageMinutes분 사용 시 cdtick 이벤트로 잠금을 트리거한다.
    private static func registerCooldownGroup(_ group: SharedStore.ScreenTimeGroup) throws {
        if SharedStore.isInCooldown(group.id) { return }

        let generation: Int
        if SharedStore.cooldownEnd(for: group.id) != nil {
            // 만료된 휴식 상태가 남아 있음(타이머 놓침) → 정리 + generation 증가 후 새 사이클.
            generation = SharedStore.endCooldownAndRecharge(for: group.id)
        } else {
            generation = SharedStore.cooldownGenerationByID[group.id] ?? 0
        }
        try CooldownMonitor.startUsageMonitoring(center: center, group: group, generation: generation)
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

    static func validDailyMonitoringGroups(
        from groups: [SharedStore.ScreenTimeGroup]
    ) -> [SharedStore.ScreenTimeGroup] {
        sanitized(groups).filter { group in
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
    }

    static func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        SharedStore.isShieldActive = false
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
            SharedStore.recordOverrideRegistration(
                activityName: activity.rawValue,
                groupID: groupID,
                overrideUntil: end,
                registeredAt: now,
                message: "registered usage-based override monitor (\(minutes)m)"
            )
        } catch {
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
            print("Failed to start override monitoring: \(error.localizedDescription)")
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
            center.stopMonitoring([
                .cooldownUsage(for: groupID, generation: generation - 1),
                .cooldownTimer(for: groupID),
            ])
            guard let group = SharedStore.group(id: groupID), group.cooldownUsageMinutes > 0 else { continue }
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
