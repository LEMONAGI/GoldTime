//
//  GoldTimeTests.swift
//  GoldTimeTests
//
//  Created by YunhakLee on 5/2/26.
//

import Testing
import Foundation
@testable import GoldTime

@MainActor
struct GoldTimeTests {

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

        #expect(ScreenTimeGroupPolicy.firstInvalidReason(for: groups) == .groupHasTooManyApps("게임"))
    }

    @Test func groupPolicyRejectsNonAppTokens() {
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

        #expect(ScreenTimeGroupPolicy.firstInvalidReason(for: groups) == .groupHasNoApps("빈 그룹"))
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
    }

    @Test func extendingOneGroupLeavesOtherLockedGroups() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let now = Date()
        let first = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let second = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS")
        SharedStore.screenTimeGroups = [first, second]
        SharedStore.shieldedGroupIDs = [first.id, second.id]

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
        #expect(SharedStore.defaults.data(forKey: "lastRequestedUnlockApplicationToken") != nil)

        SharedStore.clearLastRequestedUnlockApplicationToken()

        #expect(SharedStore.defaults.data(forKey: "lastRequestedUnlockApplicationToken") == nil)
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
