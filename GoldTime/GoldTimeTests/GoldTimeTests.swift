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
        #expect(ScreenTimeManager.dailyThresholdMinutes(limit: 10) == Array(1...10))
        #expect(ScreenTimeManager.dailyThresholdMinutes(limit: 20) == [2, 4, 6, 8, 10, 12, 14, 16, 18, 20])
        #expect(ScreenTimeManager.dailyThresholdMinutes(limit: 60) == [6, 12, 18, 24, 30, 36, 42, 48, 54, 60])

        for limit in stride(from: 10, through: 410, by: 10) {
            let thresholds = ScreenTimeManager.dailyThresholdMinutes(limit: limit)
            #expect(thresholds.count == 10)
            #expect(thresholds.last == limit)
        }
    }

    @Test func dailyThresholdMinutesHandlesEdgeLimits() {
        #expect(ScreenTimeManager.dailyThresholdMinutes(limit: 0).isEmpty)
        // 1분 연장(override) 등 maxEvents 이하 한도는 1분 단위 그대로.
        #expect(ScreenTimeManager.dailyThresholdMinutes(limit: 1) == [1])
        // 한도 변경 시 남은 예산(remaining)으로 재분배: 30분에 15분 쓰고 20분으로 바꾸면 remaining 5.
        #expect(ScreenTimeManager.dailyThresholdMinutes(limit: 5) == [1, 2, 3, 4, 5])
    }

    @Test func dailyBaselinePersistsAndClearsWithUsedTime() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let groupID = UUID()
        SharedStore.dailyBaselineByGroupID = [groupID: 15]
        #expect(SharedStore.dailyBaselineByGroupID[groupID] == 15)

        // 자정 리셋 등에서 호출되는 clearAllUsedTime이 baseline도 함께 초기화해야 한다.
        SharedStore.clearAllUsedTime()
        #expect(SharedStore.dailyBaselineByGroupID[groupID] == nil)
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

        let didChange = SharedStore.pruneShieldState(keepingGroupIDs: [keptID])

        #expect(didChange)
        #expect(SharedStore.shieldedGroupIDs == [keptID])
        #expect(SharedStore.overrideUntilByGroupID[keptID] != nil)
        #expect(SharedStore.overrideUntilByGroupID[removedID] == nil)
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

    @Test func oneMinuteExtensionNearMidnightRegistersScheduleLongEnoughToCrossMidnight() {
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
            hour: 23,
            minute: 50,
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
            #expect(Bool(false), "자정 직전 1분 연장은 성공해야 합니다.")
            return
        }
        guard let schedule = registrar.lastSchedule,
              let dates = scheduleDates(from: schedule, calendar: calendar) else {
            #expect(Bool(false), "등록된 override schedule을 Date로 복원할 수 있어야 합니다.")
            return
        }
        #expect(result.overrideUntil == now.addingTimeInterval(60))
        #expect(SharedStore.overrideUntilByGroupID[group.id] == result.overrideUntil)
        #expect(dates.end.timeIntervalSince(dates.start) >= 15 * 60)
        #expect(calendar.component(.day, from: dates.end) == 20)
        #expect(schedule.warningTime == nil)
    }

    @Test func oneMinuteExtensionDuringDayKeepsScheduleUntilEndOfDay() {
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

        guard case .success = outcome else {
            #expect(Bool(false), "낮 시간대 1분 연장은 성공해야 합니다.")
            return
        }
        guard let schedule = registrar.lastSchedule,
              let dates = scheduleDates(from: schedule, calendar: calendar) else {
            #expect(Bool(false), "등록된 override schedule을 Date로 복원할 수 있어야 합니다.")
            return
        }
        let endComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: dates.end
        )
        #expect(calendar.isDate(dates.end, inSameDayAs: now))
        #expect(endComponents.hour == 23)
        #expect(endComponents.minute == 59)
        #expect(endComponents.second == 59)
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

    @Test func overrideScheduleWindowStartsInFutureAndDoesNotEndEarly() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 19,
            hour: 10,
            minute: 0,
            second: 0
        ))!.addingTimeInterval(0.25)
        let overrideUntil = now.addingTimeInterval(60)

        let window = ScreenTimeManager.overrideScheduleWindow(
            now: now,
            overrideUntil: overrideUntil,
            calendar: calendar
        )

        #expect(window.start > now)
        #expect(window.end >= overrideUntil)
        #expect(window.end.timeIntervalSince(window.start) >= 15 * 60)
        #expect(window.warningTimeComponents != nil)
        #expect(calendar.date(from: window.startComponents) == window.start)
        #expect(calendar.date(from: window.endComponents) == window.end)
    }

    @Test func overrideScheduleWindowCanCrossMidnight() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 19,
            hour: 23,
            minute: 59,
            second: 30
        ))!
        let overrideUntil = now.addingTimeInterval(15 * 60)

        let window = ScreenTimeManager.overrideScheduleWindow(
            now: now,
            overrideUntil: overrideUntil,
            calendar: calendar
        )

        #expect(window.start > now)
        #expect(window.end >= overrideUntil)
        #expect(window.end.timeIntervalSince(window.start) >= 15 * 60)
        #expect(calendar.component(.day, from: window.end) == 20)
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

}

private func scheduleDates(
    from schedule: DeviceActivitySchedule,
    calendar: Calendar
) -> (start: Date, end: Date)? {
    guard let start = calendar.date(from: schedule.intervalStart),
          let end = calendar.date(from: schedule.intervalEnd) else {
        return nil
    }
    return (start, end)
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
