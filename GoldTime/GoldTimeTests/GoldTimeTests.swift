//
//  GoldTimeTests.swift
//  GoldTimeTests
//
//  Created by YunhakLee on 5/2/26.
//

import Testing
import Foundation
import DeviceActivity
@testable import GoldTime

@MainActor
struct GoldTimeTests {

    @Test func dailyThresholdMinutesPlacesTenEvenEventsForTenMinuteMultiples() {
        // 10분 단위 한도는 정확히 10개 이벤트가 limit/10분 간격으로 균등 배치된다.
        #expect(DailyMonitor.dailyThresholdMinutes(limit: 10) == Array(1...10))
        #expect(DailyMonitor.dailyThresholdMinutes(limit: 20) == [2, 4, 6, 8, 10, 12, 14, 16, 18, 20])
        #expect(DailyMonitor.dailyThresholdMinutes(limit: 60) == [6, 12, 18, 24, 30, 36, 42, 48, 54, 60])

        for limit in stride(from: 10, through: 410, by: 10) {
            let thresholds = DailyMonitor.dailyThresholdMinutes(limit: limit)
            #expect(thresholds.count == 10)
            #expect(thresholds.last == limit)
        }
    }

    @Test func dailyThresholdMinutesHandlesEdgeLimits() {
        #expect(DailyMonitor.dailyThresholdMinutes(limit: 0).isEmpty)
        // 1분 연장(override) 등 maxEvents 이하 한도는 1분 단위 그대로.
        #expect(DailyMonitor.dailyThresholdMinutes(limit: 1) == [1])
        // 한도 변경 시 남은 예산(remaining)으로 재분배: 30분에 15분 쓰고 20분으로 바꾸면 remaining 5.
        #expect(DailyMonitor.dailyThresholdMinutes(limit: 5) == [1, 2, 3, 4, 5])
    }

    // MARK: - 사용량 알림 단계(UsageAlertPolicy) — 틱 인덱스 기반(% 계산 아님)

    @Test func usageAlertTicksSkipsSingleTick() {
        // 틱 1개(1분 한도/예산/연장분)는 알림 없음.
        #expect(UsageAlertPolicy.ticks([]).isEmpty)
        #expect(UsageAlertPolicy.ticks([1]).isEmpty)
    }

    @Test func usageAlertTicksUsesPenultimateForShortLimits() {
        // 틱 2~9개(2~9분)는 마지막 직전 틱에 90% 한 번만.
        let two = UsageAlertPolicy.ticks([1, 2])
        #expect(two.map(\.percent) == [90])
        #expect(two.map(\.minute) == [1])

        let five = UsageAlertPolicy.ticks([1, 2, 3, 4, 5])
        #expect(five.map(\.percent) == [90])
        #expect(five.map(\.minute) == [4])

        let nine = UsageAlertPolicy.ticks(Array(1...9))
        #expect(nine.map(\.percent) == [90])
        #expect(nine.map(\.minute) == [8])
    }

    @Test func usageAlertTicksUsesFifthAndNinthForTenOrMore() {
        // 틱 10개(10분 이상)는 5번째(≈50%)·9번째(≈90%) 틱 두 번.
        let ten = UsageAlertPolicy.ticks(Array(1...10))
        #expect(ten.map(\.percent) == [50, 90])
        #expect(ten.map(\.minute) == [5, 9])

        let sixty = UsageAlertPolicy.ticks([6, 12, 18, 24, 30, 36, 42, 48, 54, 60])
        #expect(sixty.map(\.percent) == [50, 90])
        #expect(sixty.map(\.minute) == [30, 54])
    }

    @Test func usageAlertEndToEndAcrossLimits() {
        // 등록되는 threshold 배열(dailyThresholdMinutes)에 정책을 적용한 결과가 합의 경계와 맞는지.
        func alerts(_ limit: Int) -> [(percent: Int, minute: Int)] {
            UsageAlertPolicy.ticks(DailyMonitor.dailyThresholdMinutes(limit: limit))
        }
        #expect(alerts(1).isEmpty)                        // 1분: 없음
        #expect(alerts(5).map(\.percent) == [90])         // 5분 이하: 마지막 직전 1회
        #expect(alerts(5).map(\.minute) == [4])
        #expect(alerts(9).map(\.percent) == [90])         // 9분: 아직 1회
        #expect(alerts(10).map(\.percent) == [50, 90])    // 10분부터: 둘 다
        #expect(alerts(10).map(\.minute) == [5, 9])
        #expect(alerts(60).map(\.minute) == [30, 54])
    }

    // MARK: - 시간대 알림 시각(timeWindowAlertMinute) 24시간 wrap

    @Test func timeWindowAlertMinuteWrapsAround() {
        // 5분 전(offset −5): 자정 근처는 전날로 감싼다.
        #expect(NotificationService.timeWindowAlertMinute(baseMinute: 3, offset: -5) == 1438)   // 00:03 → 전날 23:58
        #expect(NotificationService.timeWindowAlertMinute(baseMinute: 0, offset: -5) == 1435)   // 00:00 → 전날 23:55
        #expect(NotificationService.timeWindowAlertMinute(baseMinute: 600, offset: -5) == 595)  // 10:00 → 09:55
        // 종료(offset +1): inclusive 끝 23:59(1439)는 자정(0)으로.
        #expect(NotificationService.timeWindowAlertMinute(baseMinute: 1439, offset: 1) == 0)
        #expect(NotificationService.timeWindowAlertMinute(baseMinute: 720, offset: 1) == 721)   // 12:00 끝 → 12:01
    }

    @Test func dailyHeartbeatScheduleIsCanonicalRepeatingMidnightWindow() {
        // 자정 재무장의 주 경로: 00:00~23:59:59, repeats:true, 이벤트 없음.
        // (date-less repeats:false 측정창의 undocumented 재무장에 의존하지 않기 위함)
        let schedule = DailyMonitor.heartbeatSchedule
        #expect(schedule.repeats == true)
        #expect(schedule.intervalStart.hour == 0)
        #expect(schedule.intervalStart.minute == 0)
        #expect(schedule.intervalEnd.hour == 23)
        #expect(schedule.intervalEnd.minute == 59)
        #expect(schedule.intervalEnd.second == 59)
    }

    @Test func heartbeatNeededOnlyWhenDailyOrCooldownGroupExists() {
        // 시간대 그룹은 window+override로 그룹당 최대 4개 activity → 5그룹 전부 시간대면 20.
        // 하트비트(+1)가 상한을 넘기지 않도록, daily/cooldown이 있을 때만 등록한다.
        func group(_ rule: SharedStore.ScreenTimeGroup.RuleKind?) -> SharedStore.ScreenTimeGroup {
            SharedStore.ScreenTimeGroup(name: "g", ruleKind: rule)
        }
        // 시간대-only / draft-only → 불필요.
        #expect(DailyMonitor.needsHeartbeat(for: []) == false)
        #expect(DailyMonitor.needsHeartbeat(for: [group(.timeWindows)]) == false)
        #expect(DailyMonitor.needsHeartbeat(for: [group(.timeWindows), group(.timeWindows)]) == false)
        #expect(DailyMonitor.needsHeartbeat(for: [group(nil)]) == false)
        // daily 또는 cooldown이 하나라도 있으면 필요.
        #expect(DailyMonitor.needsHeartbeat(for: [group(.dailyLimit)]) == true)
        #expect(DailyMonitor.needsHeartbeat(for: [group(.cooldown)]) == true)
        #expect(DailyMonitor.needsHeartbeat(for: [group(.timeWindows), group(.cooldown)]) == true)
    }

    @Test func usageBaselinesPersistAndClearWithUsedTime() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let groupID = UUID()
        SharedStore.dailyBaselineByGroupID = [groupID: 15]
        SharedStore.cooldownBaselineByGroupID = [groupID: 7]
        #expect(SharedStore.dailyBaselineByGroupID[groupID] == 15)
        #expect(SharedStore.cooldownBaselineByGroupID[groupID] == 7)

        // 자정 리셋 등에서 호출되는 clearAllUsedTime이 daily/cooldown baseline도 함께 초기화해야 한다.
        SharedStore.clearAllUsedTime()
        #expect(SharedStore.dailyBaselineByGroupID[groupID] == nil)
        #expect(SharedStore.cooldownBaselineByGroupID[groupID] == nil)
    }

    @Test func estimatedRevenueUsesConfiguredAdPrice() {
        let stats = SharedStore.DailyStats(
            dateKey: "2026-05-09",
            adWatchCount: 3,
            adUnlockedSeconds: 15 * 60,
            oneMinuteUsedCount: 2,
            shieldHitCount: 1,
            walkAwayCount: 4
        )

        #expect(stats.estimatedAdRevenueWon == 300)
        #expect(stats.totalUnlockedSeconds == 17 * 60)
        #expect(stats.walkAwayCount == 4)
    }

    @Test func morningNotificationSlotAllowsOncePerDay() {
        SharedStore.resetMorningNotificationSlot()
        defer { SharedStore.resetMorningNotificationSlot() }

        let day1 = Date()
        let day2 = Calendar.current.date(byAdding: .day, value: 1, to: day1)!

        // 같은 날: 자정 그룹별 중복 호출 + BGTask 폴백이 겹쳐도 첫 호출만 통과한다.
        #expect(SharedStore.claimMorningNotificationSlot(now: day1) == true)
        #expect(SharedStore.claimMorningNotificationSlot(now: day1) == false)
        #expect(SharedStore.claimMorningNotificationSlot(now: day1) == false)

        // 날짜가 바뀌면 다음 날 알림을 위해 다시 통과한다.
        #expect(SharedStore.claimMorningNotificationSlot(now: day2) == true)
        #expect(SharedStore.claimMorningNotificationSlot(now: day2) == false)

        // 리셋하면 같은 날도 다시 통과한다.
        SharedStore.resetMorningNotificationSlot()
        #expect(SharedStore.claimMorningNotificationSlot(now: day2) == true)
    }

    @Test func recordsTodayDashboardStats() {
        SharedStore.clearDailyStatsForTesting()
        defer { SharedStore.clearDailyStatsForTesting() }

        SharedStore.recordAdUnlock(seconds: 15 * 60)
        SharedStore.recordOneMinuteUnlock(seconds: 60)
        SharedStore.recordShieldHit()
        SharedStore.recordWalkAway()

        let stats = SharedStore.todayStats
        #expect(stats.adWatchCount == 1)
        #expect(stats.adUnlockedSeconds == 15 * 60)
        #expect(stats.oneMinuteUsedCount == 1)
        #expect(stats.shieldHitCount == 1)
        #expect(stats.walkAwayCount == 1)
        #expect(stats.estimatedAdRevenueWon == 100)
    }

    @Test func dailyStatsDecodeOldPayloadWithoutWalkAwayCount() throws {
        let payload = Data("""
        {
            "dateKey": "2026-05-09",
            "adWatchCount": 2,
            "adUnlockedSeconds": 1800,
            "oneMinuteUsedCount": 1,
            "shieldHitCount": 3
        }
        """.utf8)

        let stats = try JSONDecoder().decode(SharedStore.DailyStats.self, from: payload)

        #expect(stats.dateKey == "2026-05-09")
        #expect(stats.adWatchCount == 2)
        #expect(stats.adUnlockedSeconds == 1800)
        #expect(stats.oneMinuteUsedCount == 1)
        #expect(stats.shieldHitCount == 3)
        #expect(stats.walkAwayCount == 0)
    }

    @Test func groupPolicyRejectsMoreThanFiveGroups() {
        let groups = (0..<6).map { index in
            ScreenTimeGroupPolicy.GroupSnapshot(
                name: "그룹 \(index)",
                appTokens: ["app-\(index)"],
                dailyLimitMinutes: 10
            )
        }

        #expect(ScreenTimeGroupPolicy.firstInvalidReason(for: groups) == .tooManyGroups)
    }

    @Test func groupPolicyRejectsMoreThanNineAppsInGroup() {
        let groups = [
            ScreenTimeGroupPolicy.GroupSnapshot(
                name: "게임",
                appTokens: Set((0..<10).map { "app-\($0)" }),
                dailyLimitMinutes: 10
            )
        ]

        #expect(ScreenTimeGroupPolicy.firstInvalidReason(for: groups) == .groupHasTooManySelections("게임"))
    }

    @Test func groupPolicyAllowsWebDomainOnlyGroup() {
        let groups = [
            ScreenTimeGroupPolicy.GroupSnapshot<String>(
                name: "뉴스",
                appTokens: [],
                webDomainTokenCount: 1,
                dailyLimitMinutes: 10
            )
        ]

        #expect(ScreenTimeGroupPolicy.firstInvalidReason(for: groups) == nil)
    }

    @Test func groupPolicyCountsAppsAndWebDomainsTogether() {
        let groups = [
            ScreenTimeGroupPolicy.GroupSnapshot(
                name: "혼합",
                appTokens: Set((0..<SharedStore.maxAppsPerGroup).map { "app-\($0)" }),
                webDomainTokenCount: 1,
                dailyLimitMinutes: 10
            )
        ]

        #expect(ScreenTimeGroupPolicy.firstInvalidReason(for: groups) == .groupHasTooManySelections("혼합"))
    }

    @Test func groupPolicyRejectsUnsupportedTokens() {
        let groups = [
            ScreenTimeGroupPolicy.GroupSnapshot(
                name: "SNS",
                appTokens: ["instagram"],
                hasNonAppTokens: true,
                dailyLimitMinutes: 10
            )
        ]

        #expect(ScreenTimeGroupPolicy.firstInvalidReason(for: groups) == .groupHasNonAppTokens("SNS"))
    }

    @Test func duplicateAppsAcrossGroupsAreAllowed() {
        let groups = [
            ScreenTimeGroupPolicy.GroupSnapshot(
                name: "게임",
                appTokens: ["youtube", "game"],
                dailyLimitMinutes: 10
            ),
            ScreenTimeGroupPolicy.GroupSnapshot(
                name: "SNS",
                appTokens: ["youtube", "instagram"],
                dailyLimitMinutes: 15
            )
        ]

        #expect(ScreenTimeGroupPolicy.firstInvalidReason(for: groups) == nil)
        #expect(ScreenTimeGroupPolicy.hasDuplicateApps(in: groups))
        #expect(ScreenTimeGroupPolicy.unionAppTokens(for: groups) == Set(["youtube", "game", "instagram"]))
    }

    @Test func invalidReasonPriorityStartsWithMissingApps() {
        let groups = [
            ScreenTimeGroupPolicy.GroupSnapshot<String>(
                name: "빈 그룹",
                appTokens: [],
                dailyLimitMinutes: 0
            )
        ]

        #expect(ScreenTimeGroupPolicy.firstInvalidReason(for: groups) == .groupHasNoSelection("빈 그룹"))
    }

    @Test func shieldUnionLimitIsDefensiveEvenWhenPerGroupLimitDiffers() {
        let groups = [
            ScreenTimeGroupPolicy.GroupSnapshot(
                name: "큰 그룹",
                appTokens: Set((0..<50).map { "app-\($0)" }),
                dailyLimitMinutes: 10
            )
        ]

        let reason = ScreenTimeGroupPolicy.firstInvalidReason(
            for: groups,
            maxAppsPerGroup: 100,
            maxShieldApplications: 49
        )
        #expect(reason == .shieldApplicationLimitExceeded(50))
    }

    @Test func findsLockedGroupCandidatesForApp() {
        let groups = [
            ScreenTimeGroupPolicy.GroupSnapshot(
                name: "게임",
                appTokens: ["target", "game"],
                dailyLimitMinutes: 10
            ),
            ScreenTimeGroupPolicy.GroupSnapshot(
                name: "SNS",
                appTokens: ["target", "chat"],
                dailyLimitMinutes: 15
            ),
            ScreenTimeGroupPolicy.GroupSnapshot(
                name: "공부",
                appTokens: ["notes"],
                dailyLimitMinutes: 20
            )
        ]

        let candidates = ScreenTimeGroupPolicy.groupsContaining("target", in: groups)
        #expect(candidates.map(\.name) == ["게임", "SNS"])
    }

    @Test func monitoringEligibilityKeepsValidGroupsWhenDraftsExist() {
        let validID = UUID()
        let emptyID = UUID()
        let noLimitID = UUID()
        let groups = [
            ScreenTimeGroupPolicy.GroupSnapshot(
                id: validID,
                name: "SNS",
                appTokens: ["instagram"],
                dailyLimitMinutes: 20
            ),
            ScreenTimeGroupPolicy.GroupSnapshot<String>(
                id: emptyID,
                name: "빈 그룹",
                appTokens: [],
                dailyLimitMinutes: 20
            ),
            ScreenTimeGroupPolicy.GroupSnapshot(
                id: noLimitID,
                name: "한도 없음",
                appTokens: ["video"],
                dailyLimitMinutes: 0
            )
        ]

        let eligible = ScreenTimeGroupPolicy.monitoringEligibleGroups(from: groups)

        #expect(eligible.map(\.id) == [validID, noLimitID])
    }

    @Test func draftGroupExcludedFromMonitoringEligibility() {
        let appliedID = UUID()
        let draftID = UUID()
        let groups = [
            ScreenTimeGroupPolicy.GroupSnapshot(
                id: appliedID,
                name: "적용됨",
                appTokens: ["instagram"],
                dailyLimitMinutes: 20,
                isApplied: true
            ),
            ScreenTimeGroupPolicy.GroupSnapshot(
                id: draftID,
                name: "설정 중",
                appTokens: ["youtube"],
                dailyLimitMinutes: 20,
                isApplied: false
            )
        ]

        // draft는 자격에서 제외되고, 개별 사유는 groupNotApplied.
        #expect(ScreenTimeGroupPolicy.monitoringEligibleGroups(from: groups).map(\.id) == [appliedID])
        #expect(ScreenTimeGroupPolicy.invalidReason(for: groups[1]) == .groupNotApplied("설정 중"))
        // 그러나 저장 전체 검증(firstInvalidReason)은 draft 때문에 막히지 않는다.
        #expect(ScreenTimeGroupPolicy.firstInvalidReason(for: groups) == nil)
    }

    @Test func pruneShieldStateRemovesDeletedOrInvalidGroupsOnly() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let keptID = UUID()
        let removedID = UUID()
        let now = Date()
        SharedStore.shieldedGroupIDs = [keptID, removedID]
        SharedStore.setOverride(until: now.addingTimeInterval(60), for: keptID)
        SharedStore.setOverride(until: now.addingTimeInterval(120), for: removedID)
        SharedStore.markUsageBasedOverride(keptID)
        SharedStore.markUsageBasedOverride(removedID)
        SharedStore.recordOverrideBaseline(groupID: keptID, baseline: 3, grantedMinutes: 1)
        SharedStore.recordOverrideBaseline(groupID: removedID, baseline: 4, grantedMinutes: 10)

        let didChange = SharedStore.pruneShieldState(keepingGroupIDs: [keptID])

        #expect(didChange)
        #expect(SharedStore.shieldedGroupIDs == [keptID])
        #expect(SharedStore.overrideUntilByGroupID[keptID] != nil)
        #expect(SharedStore.overrideUntilByGroupID[removedID] == nil)
        #expect(SharedStore.usageBasedOverrideGroupIDs == [keptID])
        #expect(SharedStore.overrideBaselineUsedTimeByGroupID == [keptID: 3])
        #expect(SharedStore.overrideGrantedMinutesByGroupID == [keptID: 1])
    }

    @Test func clearAllOverrideStateKeepsLockedGroupsAndUsedTime() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let groupID = UUID()
        SharedStore.screenTimeGroups = [
            SharedStore.ScreenTimeGroup(id: groupID, name: "SNS", dailyLimitMinutes: 0)
        ]
        SharedStore.shieldedGroupIDs = [groupID]
        SharedStore.setOverride(until: Date().addingTimeInterval(60), for: groupID)
        SharedStore.markUsageBasedOverride(groupID)
        SharedStore.recordOverrideBaseline(groupID: groupID, baseline: 2, grantedMinutes: 1)
        SharedStore.usedTimeByGroupID = [groupID: 2]

        #expect(SharedStore.lockedGroups().isEmpty)
        #expect(SharedStore.clearAllOverrideState())

        #expect(SharedStore.shieldedGroupIDs == [groupID])
        #expect(SharedStore.usedTimeByGroupID == [groupID: 2])
        #expect(SharedStore.overrideUntilByGroupID.isEmpty)
        #expect(SharedStore.usageBasedOverrideGroupIDs.isEmpty)
        #expect(SharedStore.overrideBaselineUsedTimeByGroupID.isEmpty)
        #expect(SharedStore.overrideGrantedMinutesByGroupID.isEmpty)
        #expect(SharedStore.lockedGroups().map(\.id) == [groupID])
    }

    @Test func firstDailyProtectionCheckPreservesExistingShieldState() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS")
        SharedStore.screenTimeGroups = [group]
        SharedStore.shieldedGroupIDs = [group.id]
        SharedStore.isShieldActive = true

        let didReset = SharedStore.resetDailyProtectionStateIfNeeded(now: Date())

        #expect(!didReset)
        #expect(SharedStore.shieldedGroupIDs == [group.id])
        #expect(SharedStore.lockedGroups().map(\.id) == [group.id])
        #expect(SharedStore.isShieldActive)
    }

    @Test func sameDayDailyProtectionCheckPreservesLockedGroups() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let calendar = Calendar.current
        let morning = calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 9))!
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 15))!
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS")
        SharedStore.screenTimeGroups = [group]
        SharedStore.oneMinuteCounterDate = morning
        SharedStore.oneMinuteUsedToday = 2
        SharedStore.shieldedGroupIDs = [group.id]
        SharedStore.setOverride(until: afternoon.addingTimeInterval(60), for: group.id)
        SharedStore.isShieldActive = true

        #expect(!SharedStore.resetDailyProtectionStateIfNeeded(now: morning))
        #expect(!SharedStore.resetDailyProtectionStateIfNeeded(now: afternoon))

        #expect(SharedStore.shieldedGroupIDs == [group.id])
        #expect(SharedStore.overrideUntilByGroupID[group.id] != nil)
        #expect(SharedStore.oneMinuteUsedToday == 2)
        #expect(SharedStore.isShieldActive)
    }

    @Test func nextDayDailyProtectionCheckClearsLockedGroupsAndCounter() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let calendar = Calendar.current
        let firstDay = calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 23))!
        let nextDay = calendar.date(from: DateComponents(year: 2026, month: 5, day: 18, hour: 0, minute: 1))!
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS")
        SharedStore.screenTimeGroups = [group]
        SharedStore.oneMinuteCounterDate = firstDay
        SharedStore.oneMinuteUsedToday = 4
        SharedStore.shieldedGroupIDs = [group.id]
        SharedStore.setOverride(until: nextDay.addingTimeInterval(60), for: group.id)
        SharedStore.isShieldActive = true

        #expect(!SharedStore.resetDailyProtectionStateIfNeeded(now: firstDay))
        #expect(SharedStore.resetDailyProtectionStateIfNeeded(now: nextDay))

        #expect(SharedStore.shieldedGroupIDs.isEmpty)
        #expect(SharedStore.overrideUntilByGroupID.isEmpty)
        #expect(SharedStore.oneMinuteUsedToday == 0)
        #expect(calendar.isDate(SharedStore.oneMinuteCounterDate, inSameDayAs: nextDay))
        #expect(!SharedStore.isShieldActive)
    }

    @Test func nextDayDailyProtectionCheckClearsUsageBasedOverrideMetadata() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let calendar = Calendar.current
        let firstDay = calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 23))!
        let nextDay = calendar.date(from: DateComponents(year: 2026, month: 5, day: 18, hour: 0, minute: 1))!
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS")
        SharedStore.screenTimeGroups = [group]
        SharedStore.oneMinuteCounterDate = firstDay
        SharedStore.shieldedGroupIDs = [group.id]
        SharedStore.setOverride(until: firstDay.addingTimeInterval(60), for: group.id)
        SharedStore.markUsageBasedOverride(group.id)
        SharedStore.recordOverrideBaseline(groupID: group.id, baseline: 3, grantedMinutes: 1)

        #expect(!SharedStore.resetDailyProtectionStateIfNeeded(now: firstDay))
        #expect(SharedStore.resetDailyProtectionStateIfNeeded(now: nextDay))

        #expect(SharedStore.overrideUntilByGroupID.isEmpty)
        #expect(SharedStore.usageBasedOverrideGroupIDs.isEmpty)
        #expect(SharedStore.overrideBaselineUsedTimeByGroupID.isEmpty)
        #expect(SharedStore.overrideGrantedMinutesByGroupID.isEmpty)
        #expect(SharedStore.lockedGroups(now: nextDay).isEmpty)
    }

    @Test func groupOverrideOnlyRemovesSelectedGroupFromLockedGroups() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let first = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let second = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS")
        SharedStore.screenTimeGroups = [first, second]
        SharedStore.shieldedGroupIDs = [first.id, second.id]
        SharedStore.setOverride(until: Date().addingTimeInterval(60), for: first.id)

        let lockedNames = SharedStore.lockedGroups().map(\.name)
        let overrideNames = SharedStore.groupsInOverride().map(\.name)
        #expect(lockedNames == ["SNS"])
        #expect(overrideNames == ["게임"])
    }

    @Test func oneMinuteExtensionClearsSingleLockedGroup() {
        SharedStore.clearGroupStateForTesting()
        SharedStore.clearDailyStatsForTesting()
        defer {
            SharedStore.clearGroupStateForTesting()
            SharedStore.clearDailyStatsForTesting()
        }

        let now = Date()
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        SharedStore.screenTimeGroups = [group]
        SharedStore.shieldedGroupIDs = [group.id]
        SharedStore.oneMinuteUsedToday = 0
        SharedStore.oneMinuteCounterDate = now
        SharedStore.isShieldActive = true
        let registrar = FakeOverrideMonitorRegistrar()
        let originalRegistrar = ScreenTimeManager.overrideMonitorRegistrar
        ScreenTimeManager.overrideMonitorRegistrar = registrar
        defer { ScreenTimeManager.overrideMonitorRegistrar = originalRegistrar }

        let outcome = ScreenTimeManager.extendGroup(
            groupID: group.id,
            duration: 60,
            source: .oneMinute,
            now: now
        )

        guard case .success(let result) = outcome else {
            #expect(Bool(false), "1분 연장은 성공해야 합니다.")
            return
        }
        #expect(result.group.id == group.id)
        #expect(result.durationSeconds == 60)
        #expect(result.overrideUntil > now)
        #expect(SharedStore.overrideUntilByGroupID[group.id] == result.overrideUntil)
        #expect(SharedStore.lockedGroups(now: now).isEmpty)
        #expect(!SharedStore.isShieldActive)
        #expect(SharedStore.oneMinuteUsedToday == 1)
        #expect(registrar.startCallCount == 1)
        // usage-based override는 사용량 tick 이벤트로 재잠금하므로 시간 기반 warningTime을 쓰지 않는다.
        #expect(registrar.lastSchedule?.warningTime == nil)
    }

    @Test func oneMinuteExtensionRegistersDateLessScheduleUntilEndOfDay() {
        SharedStore.clearGroupStateForTesting()
        SharedStore.clearDailyStatsForTesting()
        defer {
            SharedStore.clearGroupStateForTesting()
            SharedStore.clearDailyStatsForTesting()
        }

        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 19,
            hour: 10,
            minute: 0,
            second: 0
        ))!
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        SharedStore.screenTimeGroups = [group]
        SharedStore.shieldedGroupIDs = [group.id]
        SharedStore.oneMinuteUsedToday = 0
        SharedStore.oneMinuteCounterDate = now
        SharedStore.isShieldActive = true
        let registrar = FakeOverrideMonitorRegistrar()
        let originalRegistrar = ScreenTimeManager.overrideMonitorRegistrar
        ScreenTimeManager.overrideMonitorRegistrar = registrar
        defer { ScreenTimeManager.overrideMonitorRegistrar = originalRegistrar }

        let outcome = ScreenTimeManager.extendGroup(
            groupID: group.id,
            duration: 60,
            source: .oneMinute,
            now: now
        )

        guard case .success(let result) = outcome else {
            #expect(Bool(false), "낮 시간대 1분 연장은 성공해야 합니다.")
            return
        }
        guard let schedule = registrar.lastSchedule else {
            #expect(Bool(false), "override schedule이 등록되어야 합니다.")
            return
        }
        // 측정창은 date-less여야 한다(.day/절대 날짜 컴포넌트는 threshold 즉시·배치 발화 유발).
        // intervalStart = now의 시:분:초, intervalEnd = 23:59:59, 둘 다 year/month/day 없음.
        #expect(result.overrideUntil == now.addingTimeInterval(60))
        #expect(SharedStore.overrideUntilByGroupID[group.id] == result.overrideUntil)
        #expect(schedule.intervalStart.year == nil)
        #expect(schedule.intervalStart.day == nil)
        #expect(schedule.intervalStart.hour == 10)
        #expect(schedule.intervalStart.minute == 0)
        #expect(schedule.intervalEnd.year == nil)
        #expect(schedule.intervalEnd.day == nil)
        #expect(schedule.intervalEnd.hour == 23)
        #expect(schedule.intervalEnd.minute == 59)
        #expect(schedule.intervalEnd.second == 59)
        #expect(schedule.warningTime == nil)
    }

    @Test func adExtensionClearsSingleLockedGroup() {
        SharedStore.clearGroupStateForTesting()
        SharedStore.clearDailyStatsForTesting()
        defer {
            SharedStore.clearGroupStateForTesting()
            SharedStore.clearDailyStatsForTesting()
        }

        let now = Date()
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        SharedStore.screenTimeGroups = [group]
        SharedStore.shieldedGroupIDs = [group.id]
        SharedStore.isShieldActive = true
        let registrar = FakeOverrideMonitorRegistrar()
        let originalRegistrar = ScreenTimeManager.overrideMonitorRegistrar
        ScreenTimeManager.overrideMonitorRegistrar = registrar
        defer { ScreenTimeManager.overrideMonitorRegistrar = originalRegistrar }

        let outcome = ScreenTimeManager.extendGroup(
            groupID: group.id,
            duration: 15 * 60,
            source: .adReward,
            now: now
        )

        guard case .success(let result) = outcome else {
            #expect(Bool(false), "광고 연장은 성공해야 합니다.")
            return
        }
        #expect(result.group.id == group.id)
        #expect(result.durationSeconds == 15 * 60)
        #expect(SharedStore.overrideUntilByGroupID[group.id] == result.overrideUntil)
        #expect(SharedStore.lockedGroups(now: now).isEmpty)
        #expect(!SharedStore.isShieldActive)
        #expect(SharedStore.todayStats.adWatchCount == 1)
        #expect(SharedStore.todayStats.adUnlockedSeconds == 15 * 60)
        #expect(registrar.startCallCount == 1)
    }

    @Test func relockRegistrationFailureKeepsShieldAndDoesNotConsumeOneMinute() {
        SharedStore.clearGroupStateForTesting()
        SharedStore.clearDailyStatsForTesting()
        defer {
            SharedStore.clearGroupStateForTesting()
            SharedStore.clearDailyStatsForTesting()
        }

        let now = Date()
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        SharedStore.screenTimeGroups = [group]
        SharedStore.shieldedGroupIDs = [group.id]
        SharedStore.oneMinuteUsedToday = 0
        SharedStore.oneMinuteCounterDate = now
        SharedStore.isShieldActive = true
        let registrar = FakeOverrideMonitorRegistrar(startError: TestRelockError())
        let originalRegistrar = ScreenTimeManager.overrideMonitorRegistrar
        ScreenTimeManager.overrideMonitorRegistrar = registrar
        defer { ScreenTimeManager.overrideMonitorRegistrar = originalRegistrar }

        let outcome = ScreenTimeManager.extendGroup(
            groupID: group.id,
            duration: 60,
            source: .oneMinute,
            now: now
        )

        guard case .failure(.relockTimerRegistrationFailed) = outcome else {
            #expect(Bool(false), "재잠금 타이머 등록 실패여야 합니다.")
            return
        }
        #expect(SharedStore.overrideUntilByGroupID[group.id] == nil)
        #expect(SharedStore.lockedGroups(now: now).map(\.id) == [group.id])
        #expect(SharedStore.isShieldActive)
        #expect(SharedStore.oneMinuteUsedToday == 0)
        #expect(SharedStore.todayStats.oneMinuteUsedCount == 0)
        #expect(registrar.startCallCount == 1)
    }

    // MARK: - 자정 근처 연장 (intervalTooShort 우회)

    // 시간 기반 fallback override는 usage-based가 아니라, applyShield 내부의
    // clearExpiredOverrides(now: Date())(실제 현재시각)에 의해 정리될 수 있다.
    // 따라서 endOfDay가 실제 현재보다 미래여야(=오늘 날짜) override가 유지된다.
    private func makeTime(hour: Int, minute: Int, second: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: second, of: Date())!
    }

    @Test func overrideWindowTooShortBoundaryIs2345() {
        #expect(ScreenTimeManager.overrideWindowTooShort(now: makeTime(hour: 23, minute: 44, second: 59)) == false)
        #expect(ScreenTimeManager.overrideWindowTooShort(now: makeTime(hour: 23, minute: 45, second: 0)) == true)
        #expect(ScreenTimeManager.overrideWindowTooShort(now: makeTime(hour: 14, minute: 0)) == false)
    }

    @Test func nearMidnightNoticeWindowBoundaryIs2330() {
        #expect(ScreenTimeManager.withinNearMidnightNoticeWindow(now: makeTime(hour: 23, minute: 29, second: 59)) == false)
        #expect(ScreenTimeManager.withinNearMidnightNoticeWindow(now: makeTime(hour: 23, minute: 30, second: 0)) == true)
        #expect(ScreenTimeManager.withinNearMidnightNoticeWindow(now: makeTime(hour: 23, minute: 45, second: 0)) == true)
        #expect(ScreenTimeManager.withinNearMidnightNoticeWindow(now: makeTime(hour: 14, minute: 0)) == false)
    }

    @Test func nearMidnightAdExtensionReleasesShieldWithoutMonitorUntilEndOfDay() {
        SharedStore.clearGroupStateForTesting()
        SharedStore.clearDailyStatsForTesting()
        defer {
            SharedStore.clearGroupStateForTesting()
            SharedStore.clearDailyStatsForTesting()
        }

        let now = makeTime(hour: 23, minute: 55)
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        SharedStore.screenTimeGroups = [group]
        SharedStore.shieldedGroupIDs = [group.id]
        SharedStore.isShieldActive = true
        let registrar = FakeOverrideMonitorRegistrar()
        let originalRegistrar = ScreenTimeManager.overrideMonitorRegistrar
        ScreenTimeManager.overrideMonitorRegistrar = registrar
        defer { ScreenTimeManager.overrideMonitorRegistrar = originalRegistrar }

        let outcome = ScreenTimeManager.extendGroup(
            groupID: group.id,
            duration: 10 * 60,
            source: .adReward,
            now: now
        )

        guard case .success(let result) = outcome else {
            #expect(Bool(false), "자정 근처 광고 연장은 성공해야 합니다.")
            return
        }
        // 모니터 등록 없이(시간기반 fallback) shield만 해제, override는 자정까지.
        #expect(registrar.startCallCount == 0)
        #expect(result.overrideUntil == endOfDay)
        #expect(SharedStore.overrideUntilByGroupID[group.id] == endOfDay)
        #expect(!SharedStore.usageBasedOverrideGroupIDs.contains(group.id))
        #expect(SharedStore.lockedGroups(now: now).isEmpty)
        #expect(!SharedStore.isShieldActive)
        // 통계: 횟수 +1, 시간은 자정까지 남은 만큼(= min(600, 299) = 299초).
        let secondsToMidnight = Int(endOfDay.timeIntervalSince(now))
        #expect(SharedStore.todayStats.adWatchCount == 1)
        #expect(SharedStore.todayStats.adUnlockedSeconds == secondsToMidnight)
        #expect(secondsToMidnight < 10 * 60)
    }

    @Test func nearMidnightAdExtensionRecordsTimeUntilMidnight() {
        SharedStore.clearGroupStateForTesting()
        SharedStore.clearDailyStatsForTesting()
        defer {
            SharedStore.clearGroupStateForTesting()
            SharedStore.clearDailyStatsForTesting()
        }

        let now = makeTime(hour: 23, minute: 45)
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        SharedStore.screenTimeGroups = [group]
        SharedStore.shieldedGroupIDs = [group.id]
        SharedStore.isShieldActive = true
        let registrar = FakeOverrideMonitorRegistrar()
        let originalRegistrar = ScreenTimeManager.overrideMonitorRegistrar
        ScreenTimeManager.overrideMonitorRegistrar = registrar
        defer { ScreenTimeManager.overrideMonitorRegistrar = originalRegistrar }

        let outcome = ScreenTimeManager.extendGroup(
            groupID: group.id,
            duration: 10 * 60,
            source: .adReward,
            now: now
        )

        guard case .success = outcome else {
            #expect(Bool(false), "23:45 광고 연장은 성공해야 합니다.")
            return
        }
        #expect(registrar.startCallCount == 0)
        // 통계 시간 = 자정까지 남은 시간(23:45 → 899초 ≈ 15분). grant(10분)로 cap하지 않는다.
        let secondsToMidnight = Int(endOfDay.timeIntervalSince(now))
        #expect(SharedStore.todayStats.adWatchCount == 1)
        #expect(SharedStore.todayStats.adUnlockedSeconds == secondsToMidnight)
        #expect(secondsToMidnight > 10 * 60)
    }

    @Test func nearMidnightTimeBasedOverrideRelocksAfterExpiry() {
        SharedStore.clearGroupStateForTesting()
        SharedStore.clearDailyStatsForTesting()
        defer {
            SharedStore.clearGroupStateForTesting()
            SharedStore.clearDailyStatsForTesting()
        }

        let now = makeTime(hour: 23, minute: 55)
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        SharedStore.screenTimeGroups = [group]
        SharedStore.shieldedGroupIDs = [group.id]
        SharedStore.isShieldActive = true
        let registrar = FakeOverrideMonitorRegistrar()
        let originalRegistrar = ScreenTimeManager.overrideMonitorRegistrar
        ScreenTimeManager.overrideMonitorRegistrar = registrar
        defer { ScreenTimeManager.overrideMonitorRegistrar = originalRegistrar }

        _ = ScreenTimeManager.extendGroup(groupID: group.id, duration: 10 * 60, source: .adReward, now: now)
        #expect(SharedStore.lockedGroups(now: now).isEmpty)

        // override 만료(자정 직후 시점) → foreground 복귀 보정이 시간 기반 override를 정리하고 재잠금.
        // (테스트 그룹은 토큰이 비어 있어 isShieldActive 자체는 false다. 재잠금은 lockedGroups로 검증.)
        let afterExpiry = endOfDay.addingTimeInterval(1)
        let overrideChanged = ScreenTimeManager.reapplyShieldIfOverrideExpired(now: afterExpiry)
        _ = overrideChanged
        #expect(SharedStore.overrideUntilByGroupID[group.id] == nil)
        #expect(SharedStore.lockedGroups(now: afterExpiry).map(\.id) == [group.id])
    }

    @Test func extendingOneGroupLeavesOtherLockedGroups() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let now = Date()
        let first = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let second = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS")
        SharedStore.screenTimeGroups = [first, second]
        SharedStore.shieldedGroupIDs = [first.id, second.id]
        let registrar = FakeOverrideMonitorRegistrar()
        let originalRegistrar = ScreenTimeManager.overrideMonitorRegistrar
        ScreenTimeManager.overrideMonitorRegistrar = registrar
        defer { ScreenTimeManager.overrideMonitorRegistrar = originalRegistrar }

        let outcome = ScreenTimeManager.extendGroup(
            groupID: first.id,
            duration: 60,
            source: .oneMinute,
            now: now
        )

        guard case .success(let result) = outcome else {
            #expect(Bool(false), "선택 그룹 연장은 성공해야 합니다.")
            return
        }
        #expect(result.remainingLockedGroups.map(\.id) == [second.id])
        #expect(SharedStore.lockedGroups(now: now).map(\.id) == [second.id])
    }

    @Test func expiredOverrideReturnsGroupToLockedGroups() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let calendar = Calendar(identifier: .gregorian)
        let startedAt = calendar.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 19,
            hour: 10,
            minute: 0
        ))!
        let expiredAt = startedAt.addingTimeInterval(60)
        let checkedAt = expiredAt.addingTimeInterval(1)
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        SharedStore.screenTimeGroups = [group]
        SharedStore.shieldedGroupIDs = [group.id]
        SharedStore.setOverride(until: expiredAt, for: group.id)

        #expect(SharedStore.lockedGroups(now: startedAt).isEmpty)
        #expect(SharedStore.clearExpiredOverrides(now: checkedAt))
        #expect(SharedStore.lockedGroups(now: checkedAt).map(\.id) == [group.id])
    }

    @Test func overrideActivityNameParsesGroupID() {
        let id = UUID()

        #expect(SharedStore.overrideGroupID(fromActivityName: "override.\(id.uuidString)") == id)
        #expect(SharedStore.overrideGroupID(fromActivityName: "override") == nil)
        #expect(SharedStore.overrideGroupID(fromActivityName: "override.not-a-uuid") == nil)
    }

    @Test func overrideActivityEndFallbackClearsExpiredOverrides() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 19,
            hour: 10,
            minute: 0
        ))!
        let expired = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let active = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS")
        SharedStore.screenTimeGroups = [expired, active]
        SharedStore.shieldedGroupIDs = [expired.id, active.id]
        SharedStore.setOverride(until: now.addingTimeInterval(-1), for: expired.id)
        SharedStore.setOverride(until: now.addingTimeInterval(60), for: active.id)

        let result = SharedStore.clearOverrideAfterActivityEnd(
            activityName: "override.invalid",
            now: now
        )

        #expect(result.parsedGroupID == nil)
        #expect(result.didClearOverride)
        #expect(SharedStore.overrideUntilByGroupID[expired.id] == nil)
        #expect(SharedStore.overrideUntilByGroupID[active.id] != nil)
        #expect(SharedStore.lockedGroups(now: now).map(\.id) == [expired.id])
    }

    @Test func overrideActivityEndBeforeExpiryDoesNotRelockGroup() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let now = Date()
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        SharedStore.screenTimeGroups = [group]
        SharedStore.shieldedGroupIDs = [group.id]
        SharedStore.setOverride(until: now.addingTimeInterval(60), for: group.id)

        let result = SharedStore.clearOverrideAfterActivityEnd(
            activityName: "override.\(group.id.uuidString)",
            now: now
        )

        #expect(result.parsedGroupID == group.id)
        #expect(!result.didClearOverride)
        #expect(SharedStore.overrideUntilByGroupID[group.id] != nil)
        #expect(SharedStore.lockedGroups(now: now).isEmpty)
    }

    @Test func overrideActivityEndAfterExpiryRelocksGroup() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let now = Date()
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        SharedStore.screenTimeGroups = [group]
        SharedStore.shieldedGroupIDs = [group.id]
        SharedStore.setOverride(until: now.addingTimeInterval(-1), for: group.id)

        let result = SharedStore.clearOverrideAfterActivityEnd(
            activityName: "override.\(group.id.uuidString)",
            now: now
        )

        #expect(result.parsedGroupID == group.id)
        #expect(result.didClearOverride)
        #expect(SharedStore.overrideUntilByGroupID[group.id] == nil)
        #expect(SharedStore.lockedGroups(now: now).map(\.id) == [group.id])
    }

    @Test func oneMinuteExtensionFailureDoesNotConsumeCounter() {
        SharedStore.clearGroupStateForTesting()
        SharedStore.clearDailyStatsForTesting()
        defer {
            SharedStore.clearGroupStateForTesting()
            SharedStore.clearDailyStatsForTesting()
        }

        let now = Date()
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        SharedStore.screenTimeGroups = [group]
        SharedStore.shieldedGroupIDs = [group.id]
        SharedStore.oneMinuteUsedToday = SharedStore.oneMinuteDailyLimit
        SharedStore.oneMinuteCounterDate = now

        let outcome = ScreenTimeManager.extendGroup(
            groupID: group.id,
            duration: 60,
            source: .oneMinute,
            now: now
        )

        guard case .failure(.oneMinuteLimitReached) = outcome else {
            #expect(Bool(false), "1분 횟수 초과 실패여야 합니다.")
            return
        }
        #expect(SharedStore.oneMinuteUsedToday == SharedStore.oneMinuteDailyLimit)
        #expect(SharedStore.overrideUntilByGroupID[group.id] == nil)
        #expect(SharedStore.todayStats.oneMinuteUsedCount == 0)
    }

    @Test func clearsStaleShieldApplicationToken() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        SharedStore.defaults.set(Data([1, 2, 3]), forKey: "lastRequestedUnlockApplicationToken")
        SharedStore.defaults.set(Data([4, 5, 6]), forKey: "lastRequestedUnlockWebDomainToken")
        #expect(SharedStore.defaults.data(forKey: "lastRequestedUnlockApplicationToken") != nil)
        #expect(SharedStore.defaults.data(forKey: "lastRequestedUnlockWebDomainToken") != nil)

        SharedStore.clearLastRequestedUnlockTokens()

        #expect(SharedStore.defaults.data(forKey: "lastRequestedUnlockApplicationToken") == nil)
        #expect(SharedStore.defaults.data(forKey: "lastRequestedUnlockWebDomainToken") == nil)
    }

    @Test func oneMinuteCounterIsSharedAcrossGroups() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        SharedStore.oneMinuteUsedToday = 4
        #expect(SharedStore.oneMinuteRemaining == 1)

        SharedStore.oneMinuteUsedToday += 1
        #expect(SharedStore.oneMinuteRemaining == 0)
    }

    @Test func ruleAnalyticsPayloadBucketsDailyLimit() {
        let group = SharedStore.ScreenTimeGroup(
            name: "SNS",
            dailyLimitMinutes: 75,
            ruleKind: .dailyLimit
        )

        let payload = RuleAnalyticsPayload(group: group)

        #expect(payload.ruleKind == "dailyLimit")
        #expect(payload.ruleConfigBucket == "daily_61_120m")
        #expect(payload.dailyLimitBucket == "daily_61_120m")
        #expect(payload.parameters["daily_limit_bucket"] as? String == "daily_61_120m")
        #expect(payload.parameters["selection_count_bucket"] as? String == "selection_0")
    }

    @Test func ruleAnalyticsPayloadBucketsTimeWindows() {
        let group = SharedStore.ScreenTimeGroup(
            name: "수면",
            ruleKind: .timeWindows,
            timeWindows: [
                TimeWindow(startMinuteOfDay: 8 * 60, endMinuteOfDay: 8 * 60 + 59),
                TimeWindow(startMinuteOfDay: 20 * 60, endMinuteOfDay: 21 * 60 + 59)
            ]
        )

        let payload = RuleAnalyticsPayload(group: group)

        #expect(payload.ruleKind == "timeWindows")
        #expect(payload.timeWindowCountBucket == "windows_2")
        #expect(payload.timeWindowTotalBucket == "total_61_180m")
        #expect(payload.ruleConfigBucket == "windows_2_total_61_180m")
    }

    @Test func ruleAnalyticsPayloadBucketsCooldown() {
        let group = SharedStore.ScreenTimeGroup(
            name: "게임",
            ruleKind: .cooldown,
            cooldownUsageMinutes: 30,
            cooldownDurationMinutes: 90
        )

        let payload = RuleAnalyticsPayload(group: group)

        #expect(payload.ruleKind == "cooldown")
        #expect(payload.cooldownUsageBucket == "usage_16_30m")
        #expect(payload.cooldownDurationBucket == "rest_61_120m")
        #expect(payload.ruleConfigBucket == "usage_16_30m_rest_61_120m")
    }

    @Test func adUnlockAnalyticsIncludesRulePayload() {
        let dailyGroup = SharedStore.ScreenTimeGroup(
            name: "SNS",
            dailyLimitMinutes: 75,
            ruleKind: .dailyLimit
        )
        let windowGroup = SharedStore.ScreenTimeGroup(
            name: "수면",
            ruleKind: .timeWindows,
            timeWindows: [
                TimeWindow(startMinuteOfDay: 8 * 60, endMinuteOfDay: 8 * 60 + 59)
            ]
        )
        let cooldownGroup = SharedStore.ScreenTimeGroup(
            name: "게임",
            ruleKind: .cooldown,
            cooldownUsageMinutes: 30,
            cooldownDurationMinutes: 90
        )

        let daily = AnalyticsEvent.adUnlock(seconds: 600, payload: RuleAnalyticsPayload(group: dailyGroup)).parameters
        let timeWindows = AnalyticsEvent.adUnlock(seconds: 300, payload: RuleAnalyticsPayload(group: windowGroup)).parameters
        let cooldown = AnalyticsEvent.adUnlock(seconds: 120, payload: RuleAnalyticsPayload(group: cooldownGroup)).parameters

        #expect(daily["seconds"] as? Int == 600)
        #expect(daily["rule_kind"] as? String == "dailyLimit")
        #expect(daily["rule_config_bucket"] as? String == "daily_61_120m")

        #expect(timeWindows["seconds"] as? Int == 300)
        #expect(timeWindows["rule_kind"] as? String == "timeWindows")
        #expect(timeWindows["rule_config_bucket"] as? String == "windows_1_total_15_60m")

        #expect(cooldown["seconds"] as? Int == 120)
        #expect(cooldown["rule_kind"] as? String == "cooldown")
        #expect(cooldown["rule_config_bucket"] as? String == "usage_16_30m_rest_61_120m")
    }

}

private struct TestRelockError: LocalizedError {
    var errorDescription: String? { "test relock registration failure" }
}

private final class FakeOverrideMonitorRegistrar: OverrideMonitorRegistering {
    private let startError: Error?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastActivity: DeviceActivityName?
    private(set) var lastSchedule: DeviceActivitySchedule?

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func stopMonitoring(_ activities: [DeviceActivityName]) {
        stopCallCount += 1
    }

    func startMonitoring(
        _ activity: DeviceActivityName,
        during schedule: DeviceActivitySchedule,
        events: [DeviceActivityEvent.Name: DeviceActivityEvent]
    ) throws {
        startCallCount += 1
        lastActivity = activity
        lastSchedule = schedule
        if let startError {
            throw startError
        }
    }
}
