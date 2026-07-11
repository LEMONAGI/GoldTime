//
//  CooldownTests.swift
//  GoldTimeTests
//
//  쿨다운 모드 데이터 모델(Codable 하위 호환)과 순수 정책 검증.
//

import Testing
import Foundation
import DeviceActivity
import FamilyControls
@testable import GoldTime

@MainActor
struct CooldownTests {

    // MARK: - ScreenTimeGroup Codable 라운드트립

    @Test func cooldownGroupRoundTripsThroughCodable() throws {
        // ruleKind=.cooldown, usage/cooldown이 인코딩 → 디코딩 후 보존되고 Equatable 일치.
        let group = SharedStore.ScreenTimeGroup(
            name: "쿨다운 그룹",
            ruleKind: .cooldown,
            isApplied: true,
            cooldownUsageMinutes: 20,
            cooldownDurationMinutes: 60
        )

        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(SharedStore.ScreenTimeGroup.self, from: data)

        #expect(decoded.ruleKind == .cooldown)
        #expect(decoded.cooldownUsageMinutes == 20)
        #expect(decoded.cooldownDurationMinutes == 60)
        #expect(decoded == group)
    }

    // MARK: - 구버전 페이로드 하위 호환

    /// cooldown 키가 없는 구버전 페이로드를 재현한다.
    /// (TimeWindowTests.legacyPayload 패턴 참고)
    private func legacyPayloadWithoutCooldownKeys(id: UUID, name: String, dailyLimitMinutes: Int) throws -> Data {
        let group = SharedStore.ScreenTimeGroup(id: id, name: name, dailyLimitMinutes: dailyLimitMinutes)
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(group)
        ) as! [String: Any]
        json.removeValue(forKey: "cooldownUsageMinutes")
        json.removeValue(forKey: "cooldownDurationMinutes")
        return try JSONSerialization.data(withJSONObject: json)
    }

    @Test func legacyGroupPayloadEqualsDefaultInitGroup() throws {
        // 업데이트 직후 cooldown 키 없는 구버전 페이로드가 기본 init 그룹과 Equatable 일치해야
        // syncDailyMonitoring이 불필요한 재등록을 하지 않는다.
        let id = UUID()
        let payload = try legacyPayloadWithoutCooldownKeys(id: id, name: "게임", dailyLimitMinutes: 45)
        let decoded = try JSONDecoder().decode(SharedStore.ScreenTimeGroup.self, from: payload)

        let constructed = SharedStore.ScreenTimeGroup(id: id, name: "게임", dailyLimitMinutes: 45)

        // cooldown 필드가 기본값(10/300)으로 채워져야 한다.
        #expect(decoded.cooldownUsageMinutes == SharedStore.ScreenTimeGroup.defaultCooldownUsageMinutes)
        #expect(decoded.cooldownDurationMinutes == SharedStore.ScreenTimeGroup.defaultCooldownDurationMinutes)
        #expect(decoded == constructed)
    }

    // MARK: - CooldownPolicy 경계값

    @Test func cooldownPolicyRejectsOutOfRangeUsage() {
        // 4분(최소 미만) → usageOutOfRange
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 4, cooldownMinutes: 300) == .usageOutOfRange)
        // 121분(2시간 초과) → usageOutOfRange
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 121, cooldownMinutes: 300) == .usageOutOfRange)
        // 경계: 5분, 120분 → nil
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 5, cooldownMinutes: 300) == nil)
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 120, cooldownMinutes: 300) == nil)
    }

    @Test func cooldownPolicyRejectsOutOfRangeCooldown() {
        // 29분(최소 미만) → cooldownOutOfRange
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 10, cooldownMinutes: 29) == .cooldownOutOfRange)
        // 361분(6시간 초과) → cooldownOutOfRange
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 10, cooldownMinutes: 361) == .cooldownOutOfRange)
        // 경계: 30분, 360분 → nil
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 10, cooldownMinutes: 30) == nil)
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 10, cooldownMinutes: 360) == nil)
    }

    @Test func cooldownPolicyAcceptsDefaultValues() {
        // 기본값(10/300)은 정책을 통과한다.
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 10, cooldownMinutes: 300) == nil)
    }

    // MARK: - ScreenTimeGroupPolicy cooldown 인지

    @Test func groupPolicyRejectsCooldownWithInvalidUsage() {
        // ruleKind=.cooldown + 잘못된 usage(0) → .groupHasInvalidCooldown(...)
        let groups = [
            ScreenTimeGroupPolicy.GroupSnapshot(
                name: "쿨다운 그룹",
                appTokens: ["app-1"],
                dailyLimitMinutes: 30,
                ruleKind: .cooldown,
                cooldownUsageMinutes: 0,
                cooldownDurationMinutes: 300
            )
        ]
        #expect(
            ScreenTimeGroupPolicy.firstInvalidReason(for: groups)
                == .groupHasInvalidCooldown("쿨다운 그룹", .usageOutOfRange)
        )
    }

    @Test func groupPolicyAcceptsValidCooldownGroup() {
        // 정상 cooldown 그룹 → nil
        let groups = [
            ScreenTimeGroupPolicy.GroupSnapshot(
                name: "쿨다운 그룹",
                appTokens: ["app-1"],
                dailyLimitMinutes: 30,
                ruleKind: .cooldown,
                cooldownUsageMinutes: 10,
                cooldownDurationMinutes: 300
            )
        ]
        #expect(ScreenTimeGroupPolicy.firstInvalidReason(for: groups) == nil)
    }

    // MARK: - SharedStore 쿨다운 상태 헬퍼

    private func makeCooldownGroup(id: UUID = UUID(), isApplied: Bool = true) -> SharedStore.ScreenTimeGroup {
        SharedStore.ScreenTimeGroup(
            id: id,
            name: "쿨다운 그룹",
            ruleKind: .cooldown,
            isApplied: isApplied,
            cooldownUsageMinutes: 10,
            cooldownDurationMinutes: 300
        )
    }

    private func futureDate(byMinutes minutes: Double) -> Date {
        Date().addingTimeInterval(minutes * 60)
    }

    private func pastDate(byMinutes minutes: Double) -> Date {
        Date().addingTimeInterval(-minutes * 60)
    }

    // 1. startCooldown → isInCooldown true(until 전) / false(until 후) + shieldedGroupIDs 포함.
    @Test func startCooldownMarksShieldedAndIsInCooldown() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let id = UUID()
        let future = futureDate(byMinutes: 60)

        SharedStore.startCooldown(until: future, for: id)

        #expect(SharedStore.isInCooldown(id))
        #expect(SharedStore.shieldedGroupIDs.contains(id))
        #expect(SharedStore.cooldownEnd(for: id) == future)

        // until 이후에는 isInCooldown이 false(만료 판정)
        let afterUntil = future.addingTimeInterval(1)
        #expect(!SharedStore.isInCooldown(id, now: afterUntil))
    }

    // 2. endCooldownAndRecharge → cooldownUntil 제거, shielded 해제, used/baseline 초기화, generation 0→1→2 증가.
    @Test func endCooldownAndRechargeIncrementsGeneration() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let id = UUID()
        SharedStore.startCooldown(until: futureDate(byMinutes: 60), for: id)
        SharedStore.usedTimeByGroupID = [id: 10]
        SharedStore.cooldownBaselineByGroupID = [id: 5]
        #expect(SharedStore.isInCooldown(id))

        // generation: 0 → 1
        let gen1 = SharedStore.endCooldownAndRecharge(for: id)
        #expect(gen1 == 1)
        #expect(!SharedStore.isInCooldown(id))
        #expect(!SharedStore.shieldedGroupIDs.contains(id))
        #expect(SharedStore.cooldownEnd(for: id) == nil)
        #expect(SharedStore.usedTimeByGroupID[id] == nil)
        #expect(SharedStore.cooldownBaselineByGroupID[id] == nil)

        // generation: 1 → 2 (두 번째 사이클)
        SharedStore.startCooldown(until: futureDate(byMinutes: 60), for: id)
        let gen2 = SharedStore.endCooldownAndRecharge(for: id)
        #expect(gen2 == 2)
        #expect(SharedStore.cooldownGenerationByID[id] == 2)
    }

    // 3. 자정 시뮬레이션: 쿨다운은 일일 한도와 같이 자정 리셋에서 함께 해제된다.
    //    (23:45 잠금 → 자정에 풀리고 예산 새로 충전되는 동작)
    @Test func midnightResetClearsCooldown() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let calendar = Calendar.current
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 23, minute: 0))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 0, minute: 1))!
        let cooldownUntil = calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 4, minute: 0))!

        let id = UUID()
        SharedStore.screenTimeGroups = [makeCooldownGroup(id: id)]
        SharedStore.oneMinuteCounterDate = today

        // 쿨다운 시작(원래 새벽 4시까지)
        SharedStore.startCooldown(until: cooldownUntil, for: id)
        #expect(SharedStore.shieldedGroupIDs.contains(id))

        // 자정 리셋 트리거 → 쿨다운이 끝나기 전이라도 자정에 함께 해제된다.
        let didReset = SharedStore.resetDailyProtectionStateIfNeeded(now: tomorrow)
        #expect(didReset)

        #expect(SharedStore.cooldownEnd(for: id) == nil)
        #expect(!SharedStore.shieldedGroupIDs.contains(id))
    }

    // 6. pruneShieldState: 삭제된 그룹의 cooldownUntil/generation 제거, 유효 그룹은 유지.
    @Test func pruneShieldStateRemovesDeletedCooldownGroup() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let keepID = UUID()
        let removeID = UUID()

        SharedStore.startCooldown(until: futureDate(byMinutes: 60), for: keepID)
        SharedStore.startCooldown(until: futureDate(byMinutes: 60), for: removeID)
        _ = SharedStore.endCooldownAndRecharge(for: removeID)
        SharedStore.cooldownBaselineByGroupID = [keepID: 3, removeID: 7]

        #expect(SharedStore.cooldownUntilByGroupID[keepID] != nil)
        // removeID는 endCooldownAndRecharge로 until이 제거됐지만 generation은 남아있음
        #expect(SharedStore.cooldownGenerationByID[removeID] != nil)

        // keepID만 유효·존재 그룹으로 전달(removeID는 삭제 → gen/baseline까지 prune 대상).
        let changed = SharedStore.pruneShieldState(
            keepingGroupIDs: [keepID],
            keepingCooldownProgressGroupIDs: [keepID]
        )
        #expect(changed)

        // keepID: until/generation 유지
        #expect(SharedStore.cooldownUntilByGroupID[keepID] != nil)
        // removeID: generation 제거
        #expect(SharedStore.cooldownGenerationByID[removeID] == nil)
        #expect(SharedStore.cooldownBaselineByGroupID == [keepID: 3])
    }

    // 6-1. clearCooldownCycle: 규칙 전환 시 휴식 사이클만 정리하고 usedTime은 보존, generation은 +1.
    @Test func clearCooldownCycleClearsRestButKeepsUsedTime() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let id = UUID()
        SharedStore.startCooldown(until: futureDate(byMinutes: 60), for: id)
        SharedStore.usedTimeByGroupID = [id: 10]
        SharedStore.cooldownBaselineByGroupID = [id: 10]
        #expect(SharedStore.isInCooldown(id))

        let nextGen = SharedStore.clearCooldownCycle(for: id)

        // 휴식 플래그/baseline 제거, generation +1, usedTime은 보존(전환된 규칙이 이어 사용)
        #expect(nextGen == 1)
        #expect(!SharedStore.isInCooldown(id))
        #expect(SharedStore.cooldownEnd(for: id) == nil)
        #expect(SharedStore.cooldownBaselineByGroupID[id] == nil)
        #expect(SharedStore.usedTimeByGroupID[id] == 10)
        #expect(SharedStore.cooldownGenerationByID[id] == 1)
    }

    // 6-2. 좀비 휴식 회귀: 쿨다운 휴식 중 → 다른 규칙 전환(clearCooldownCycle) 후 다시 쿨다운으로 돌아와도
    //      isInCooldown이 false라 registerCooldownGroup이 early-return하지 않고 정상 등록될 수 있다.
    @Test func ruleSwitchAwayFromCooldownClearsZombieRest() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let id = UUID()
        // 1) 쿨다운 휴식 진입 (10분 사용 후 잠김)
        SharedStore.startCooldown(until: futureDate(byMinutes: 60), for: id)
        SharedStore.usedTimeByGroupID = [id: 10]
        #expect(SharedStore.isInCooldown(id))

        // 2) 일일 등 다른 규칙으로 전환 → 휴식 사이클 정리(usedTime 보존)
        SharedStore.clearCooldownCycle(for: id)

        // 3) 다시 쿨다운으로 돌아온 시점: 좀비 플래그가 없어 .keepCooldownRest 함정에 빠지지 않는다.
        #expect(!SharedStore.isInCooldown(id))
        let action = ScreenTimeManager.cooldownEditAction(
            isInCooldown: SharedStore.isInCooldown(id),
            usedMinutes: SharedStore.usedTimeByGroupID[id] ?? 0,
            budgetMinutes: 15,
            nearMidnight: false
        )
        #expect(action == .registerAvailable)
    }

    // 7. expiredCooldownGroupIDs: 과거 until 그룹만 반환, 미래 until·비-cooldown 그룹은 제외.
    @Test func expiredCooldownGroupIDsReturnsOnlyExpired() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let activeID = UUID()
        let expiredID = UUID()
        let dailyID = UUID()

        SharedStore.screenTimeGroups = [
            makeCooldownGroup(id: activeID),
            makeCooldownGroup(id: expiredID),
            SharedStore.ScreenTimeGroup(id: dailyID, name: "게임", ruleKind: .dailyLimit, isApplied: true)
        ]

        SharedStore.startCooldown(until: futureDate(byMinutes: 60), for: activeID)
        SharedStore.startCooldown(until: pastDate(byMinutes: 1), for: expiredID)
        // dailyID는 cooldownUntil 없음

        let expired = SharedStore.expiredCooldownGroupIDs()
        #expect(expired.count == 1)
        #expect(expired.contains(expiredID))
        #expect(!expired.contains(activeID))
        #expect(!expired.contains(dailyID))
    }

    // MARK: - 쿨다운 baseline 보정

    @Test func cooldownUsageThresholdsSubtractExistingUsageBaseline() {
        // 30분 예산에서 이미 5분 사용했으면 변경 후 새 모니터는 남은 25분만 측정한다.
        let thresholds = CooldownMonitor.usageThresholds(forBudget: 30, baseline: 5)
        #expect(thresholds.last == 25)
        #expect(thresholds.allSatisfy { $0 <= 25 })

        // 이미 예산을 다 쓴 상태는 등록할 threshold가 없다(상위 sync가 즉시 휴식 처리).
        #expect(CooldownMonitor.usageThresholds(forBudget: 30, baseline: 30).isEmpty)
        #expect(CooldownMonitor.usageThresholds(forBudget: 30, baseline: 35).isEmpty)
    }

    @Test func cooldownTickRestoresAbsoluteUsedTimeFromBaseline() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let id = UUID()
        SharedStore.cooldownBaselineByGroupID = [id: 5]

        let baseline = SharedStore.cooldownBaselineByGroupID[id] ?? 0
        let used = SharedStore.raiseUsedTime(
            to: CooldownMonitor.absoluteUsedMinutes(baseline: baseline, tickMinute: 25),
            for: id
        )

        #expect(used == 30)
        #expect(SharedStore.usedTimeByGroupID[id] == 30)
    }

    // MARK: - 쿨다운 휴식 종료 자정 clamp

    @Test func cooldownEndKeepsSameDayRestEnd() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 23, minute: 0))!
        let expected = calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 23, minute: 30))!

        let end = CooldownMonitor.cooldownEnd(now: now, durationMinutes: 30, calendar: calendar)

        #expect(end == expected)
    }

    @Test func cooldownEndClampsRestThatCrossesMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 23, minute: 45))!
        let expected = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 17, hour: 23, minute: 59, second: 59)
        )!

        let end = CooldownMonitor.cooldownEnd(now: now, durationMinutes: 60, calendar: calendar)

        #expect(end == expected)
    }

    @Test func cooldownEndKeepsEarlyMorningSameDayRestEnd() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 0, minute: 10))!
        let expected = calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 0, minute: 40))!

        let end = CooldownMonitor.cooldownEnd(now: now, durationMinutes: 30, calendar: calendar)

        #expect(end == expected)
    }

    // MARK: - 편집 시 즉시 잠금 결정 (cooldownEditAction 순수 판정)

    /// 사용자 시나리오: 쿨다운 20분/1시간휴식, 15분 사용 후 예산을 5분으로 변경.
    /// 평소(자정 아님)엔 예산 소진이므로 즉시 휴식 진입.
    @Test func cooldownEditActionEntersRestWhenBudgetExceededNormally() {
        let action = ScreenTimeManager.cooldownEditAction(
            isInCooldown: false, usedMinutes: 15, budgetMinutes: 5, nearMidnight: false
        )
        #expect(action == .enterCooldownRest)
    }

    /// 같은 입력이라도 자정 직전이면 휴식 타이머 없이 잠금만(자정 리셋이 재충전).
    @Test func cooldownEditActionLocksUntilMidnightWhenBudgetExceededNearMidnight() {
        let action = ScreenTimeManager.cooldownEditAction(
            isInCooldown: false, usedMinutes: 15, budgetMinutes: 5, nearMidnight: true
        )
        #expect(action == .lockUntilMidnight)
    }

    /// 경계: used == budget도 소진으로 본다(>=).
    @Test func cooldownEditActionTreatsEqualUsageAsExceeded() {
        #expect(ScreenTimeManager.cooldownEditAction(
            isInCooldown: false, usedMinutes: 5, budgetMinutes: 5, nearMidnight: false
        ) == .enterCooldownRest)
    }

    /// 예산이 남으면 평소엔 기존 잠금을 풀고 남은 예산을 측정, 자정 직전엔 미추적 스킵.
    @Test func cooldownEditActionRegistersAvailableOrSkipsWhenBudgetRemains() {
        #expect(ScreenTimeManager.cooldownEditAction(
            isInCooldown: false, usedMinutes: 3, budgetMinutes: 5, nearMidnight: false
        ) == .registerAvailable)
        #expect(ScreenTimeManager.cooldownEditAction(
            isInCooldown: false, usedMinutes: 3, budgetMinutes: 5, nearMidnight: true
        ) == .skipUntracked)
    }

    /// 이미 휴식 중이면 예산/시각과 무관하게 휴식을 유지한다(registerCooldownGroup이 early-return).
    @Test func cooldownEditActionKeepsCooldownRestWhenAlreadyResting() {
        #expect(ScreenTimeManager.cooldownEditAction(
            isInCooldown: true, usedMinutes: 99, budgetMinutes: 5, nearMidnight: true
        ) == .keepCooldownRest)
        #expect(ScreenTimeManager.cooldownEditAction(
            isInCooldown: true, usedMinutes: 0, budgetMinutes: 5, nearMidnight: false
        ) == .keepCooldownRest)
    }

    // MARK: - 재동기화 stop 대상 결정 (cooldownActivitiesToStop 순수 판정)

    /// 변경 없는 유효 쿨다운 그룹은 재등록 churn 방지를 위해 아무것도 멈추지 않는다.
    @Test func cooldownActivitiesToStopReturnsNothingWhenUnchanged() {
        let id = UUID()
        let stop = ScreenTimeManager.cooldownActivitiesToStop(
            groupID: id, generation: 3,
            isStillCooldown: true, isUnchanged: true, isInCooldownRest: false
        )
        #expect(stop.isEmpty)
    }

    /// 핵심: 휴식 중인 쿨다운 그룹을 편집하면 휴식 타이머는 보존하고 사용 예산 activity만 멈춘다.
    @Test func cooldownActivitiesToStopPreservesTimerWhileResting() {
        let id = UUID()
        let stop = ScreenTimeManager.cooldownActivitiesToStop(
            groupID: id, generation: 2,
            isStillCooldown: true, isUnchanged: false, isInCooldownRest: true
        )
        #expect(stop == [.cooldownUsage(for: id, generation: 2)])
        #expect(!stop.contains(.cooldownTimer(for: id)))
    }

    /// 휴식이 아닌 변경(예산만 조정 등)은 사용 예산·휴식 타이머를 둘 다 멈췄다가 재등록한다.
    @Test func cooldownActivitiesToStopStopsBothWhenChangedAndNotResting() {
        let id = UUID()
        let stop = ScreenTimeManager.cooldownActivitiesToStop(
            groupID: id, generation: 1,
            isStillCooldown: true, isUnchanged: false, isInCooldownRest: false
        )
        #expect(stop.contains(.cooldownUsage(for: id, generation: 1)))
        #expect(stop.contains(.cooldownTimer(for: id)))
    }

    /// 쿨다운에서 벗어난(삭제/규칙 전환) 그룹은 휴식 중이어도 타이머까지 정리한다.
    @Test func cooldownActivitiesToStopStopsBothWhenNoLongerCooldown() {
        let id = UUID()
        let stop = ScreenTimeManager.cooldownActivitiesToStop(
            groupID: id, generation: 0,
            isStillCooldown: false, isUnchanged: false, isInCooldownRest: true
        )
        #expect(stop.contains(.cooldownUsage(for: id, generation: 0)))
        #expect(stop.contains(.cooldownTimer(for: id)))
    }

    // MARK: - 타이머-종료 재충전 판정 (shouldRechargeOnTimerEnd 순수 판정)

    /// cooldownEnd가 없으면(이미 해제/자정 리셋) 중복 재충전하지 않는다.
    @Test func shouldRechargeOnTimerEndIsFalseWhenNoCooldownEnd() {
        #expect(CooldownMonitor.shouldRechargeOnTimerEnd(cooldownEnd: nil, now: Date()) == false)
    }

    /// 종료 예정 시각이 미래면(설정 변경 등으로 일찍 멈춤) 휴식을 보존하고 재충전하지 않는다.
    @Test func shouldRechargeOnTimerEndIsFalseWhenEndInFuture() {
        #expect(CooldownMonitor.shouldRechargeOnTimerEnd(
            cooldownEnd: futureDate(byMinutes: 10), now: Date()
        ) == false)
    }

    /// 종료 예정 시각이 과거이거나 현재면(실제 휴식 종료) 재충전한다.
    @Test func shouldRechargeOnTimerEndIsTrueWhenEndPassed() {
        #expect(CooldownMonitor.shouldRechargeOnTimerEnd(
            cooldownEnd: pastDate(byMinutes: 1), now: Date()
        ) == true)
        let now = Date()
        #expect(CooldownMonitor.shouldRechargeOnTimerEnd(cooldownEnd: now, now: now) == true)
    }

    // MARK: - 재충전 실패 시 등록 기록 정리 (clearRegistration)

    /// 재충전 등록 실패 경로가 호출하는 clearRegistration은 해당 그룹만 churn 가드에서 비우고
    /// 나머지 등록은 보존한다 → 다음 foreground sync가 실패 그룹만 즉시 재등록(영구 스킵 방지).
    @Test func clearRegistrationRemovesOnlyTargetGroup() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let failedID = UUID()
        let keptID = UUID()
        SharedStore.lastRegisteredGroupsByID = [
            failedID: makeCooldownGroup(id: failedID),
            keptID: makeCooldownGroup(id: keptID)
        ]

        SharedStore.clearRegistration(for: failedID)

        let registered = SharedStore.lastRegisteredGroupsByID ?? [:]
        #expect(registered[failedID] == nil)
        #expect(registered[keptID] != nil)
    }

    /// 기록이 비어 있어도(nil) clearRegistration은 안전하게 no-op이다.
    @Test func clearRegistrationIsSafeWhenEmpty() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        SharedStore.clearRegistration(for: UUID())
        #expect(SharedStore.lastRegisteredGroupsByID == nil)
    }

    // MARK: - 휴식 재충전 시 연장 상태 청산 (좀비 잠금 회귀)

    /// 진행 중이던 연장(광고/1분)이 있는 채로 휴식이 재충전되면, endCooldownAndRecharge가
    /// override 상태를 함께 청산해야 살아남은 연장의 소진 tick이 좀비 잠금을 만들지 않는다.
    @Test func endCooldownAndRechargeClearsOverrideState() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let id = UUID()
        SharedStore.startCooldown(until: futureDate(byMinutes: 60), for: id)
        // 연장(광고/1분) 진행 중 상태 구성: overrideUntil + usage 기반 마킹 + baseline/grant.
        SharedStore.setOverride(until: futureDate(byMinutes: 10), for: id)
        SharedStore.markUsageBasedOverride(id)
        SharedStore.recordOverrideBaseline(groupID: id, baseline: 3, grantedMinutes: 5)

        _ = SharedStore.endCooldownAndRecharge(for: id)

        #expect(SharedStore.overrideUntilByGroupID[id] == nil)
        #expect(!SharedStore.usageBasedOverrideGroupIDs.contains(id))
        #expect(SharedStore.overrideBaselineUsedTimeByGroupID[id] == nil)
        #expect(SharedStore.overrideGrantedMinutesByGroupID[id] == nil)
    }

    // MARK: - 연장 소진 재잠금 판정 (shouldReshieldOnOverrideExhaustion 순수 판정)

    /// 쿨다운 그룹은 휴식이 진행 중일 때만 소진 재잠금한다. 휴식이 이미 재충전된 뒤 살아남은
    /// 연장의 소진은 좀비 잠금을 막기 위해 재잠금하지 않는다. 쿨다운 아닌 규칙은 항상 재잠금.
    @Test func shouldReshieldOnOverrideExhaustionJudgment() {
        // 쿨다운 아님 → 항상 재잠금(true).
        #expect(CooldownMonitor.shouldReshieldOnOverrideExhaustion(
            isCooldownRule: false, isInCooldown: false
        ))
        // 쿨다운 + 휴식 진행 중 → 재잠금(true).
        #expect(CooldownMonitor.shouldReshieldOnOverrideExhaustion(
            isCooldownRule: true, isInCooldown: true
        ))
        // 쿨다운 + 휴식 이미 재충전됨 → 재잠금 안 함(false).
        #expect(!CooldownMonitor.shouldReshieldOnOverrideExhaustion(
            isCooldownRule: true, isInCooldown: false
        ))
    }
}
