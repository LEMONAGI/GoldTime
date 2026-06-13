//
//  TimeWindowTests.swift
//  GoldTimeTests
//
//  시간대별 차단 규칙의 모델(Codable 하위 호환)과 순수 정책 검증.
//

import Testing
import Foundation
import DeviceActivity
import FamilyControls
@testable import GoldTime

@MainActor
struct TimeWindowTests {

    // MARK: - TimeWindow 판정

    @Test func timeWindowContainsIsBothInclusive() {
        let window = SharedStore.TimeWindow(startMinuteOfDay: 600, endMinuteOfDay: 719) // 10:00-11:59(inclusive)

        #expect(window.contains(minuteOfDay: 600))   // 시작 분 포함
        #expect(window.contains(minuteOfDay: 719))   // 종료 분(11:59) 포함
        #expect(!window.contains(minuteOfDay: 599))  // 시작 직전 미포함
        #expect(!window.contains(minuteOfDay: 720))  // 종료 다음 분(12:00) 미포함
        #expect(window.durationMinutes == 120)       // 600...719 = 120분
    }

    @Test func minuteOfDayConvertsClockTime() {
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 13, minute: 45))!

        #expect(SharedStore.minuteOfDay(for: date) == 13 * 60 + 45)

        let midnight = calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 0, minute: 0))!
        #expect(SharedStore.minuteOfDay(for: midnight) == 0)
    }

    // MARK: - TimeWindowPolicy 검증

    @Test func timeWindowPolicyRejectsEmptyAndTooMany() {
        #expect(TimeWindowPolicy.firstInvalidReason(for: []) == .empty)

        let four = (0..<4).map { index in
            TimeWindow(startMinuteOfDay: index * 120, endMinuteOfDay: index * 120 + 60)
        }
        #expect(TimeWindowPolicy.firstInvalidReason(for: four) == .tooMany)
    }

    @Test func timeWindowPolicyRejectsMidnightCrossingAndShortWindows() {
        // 22:00-02:00처럼 start > end는 자정 넘김으로 본다.
        let crossing = [TimeWindow(startMinuteOfDay: 22 * 60, endMinuteOfDay: 2 * 60)]
        #expect(TimeWindowPolicy.firstInvalidReason(for: crossing) == .crossesMidnight)

        // start == end는 inclusive 1분짜리 시간대 → 자정 넘김이 아니라 너무 짧음으로 본다.
        let oneMinute = [TimeWindow(startMinuteOfDay: 600, endMinuteOfDay: 600)]
        #expect(TimeWindowPolicy.firstInvalidReason(for: oneMinute) == .tooShort)

        // DeviceActivity 최소 interval(15분) 미만은 등록이 실패하므로 사전 차단.
        let short = [TimeWindow(startMinuteOfDay: 600, endMinuteOfDay: 610)]
        #expect(TimeWindowPolicy.firstInvalidReason(for: short) == .tooShort)
    }

    @Test func timeWindowPolicyRejectsOutOfRangeMinutes() {
        let negativeStart = [TimeWindow(startMinuteOfDay: -10, endMinuteOfDay: 60)]
        #expect(TimeWindowPolicy.firstInvalidReason(for: negativeStart) == .outOfRange)

        // 종료는 23:59(1439)까지만 허용한다.
        let pastMidnight = [TimeWindow(startMinuteOfDay: 23 * 60, endMinuteOfDay: 24 * 60)]
        #expect(TimeWindowPolicy.firstInvalidReason(for: pastMidnight) == .outOfRange)
    }

    @Test func timeWindowPolicyRejectsOverlapAndBoundarySharing() {
        let overlapping = [
            TimeWindow(startMinuteOfDay: 600, endMinuteOfDay: 720),
            TimeWindow(startMinuteOfDay: 700, endMinuteOfDay: 780)
        ]
        #expect(TimeWindowPolicy.firstInvalidReason(for: overlapping) == .overlapping)

        // end가 inclusive이므로 12:00–13:00 + 13:00–14:00은 13:00을 둘 다 차단 → 겹침으로 거부.
        let boundarySharing = [
            TimeWindow(startMinuteOfDay: 12 * 60, endMinuteOfDay: 13 * 60),
            TimeWindow(startMinuteOfDay: 13 * 60, endMinuteOfDay: 14 * 60)
        ]
        #expect(TimeWindowPolicy.firstInvalidReason(for: boundarySharing) == .overlapping)

        // 연속 차단은 12:00–12:59 + 13:00–14:00처럼 1분 띄워 표현하면 허용된다(겹침 없음).
        let contiguous = [
            TimeWindow(startMinuteOfDay: 12 * 60, endMinuteOfDay: 13 * 60 - 1),
            TimeWindow(startMinuteOfDay: 13 * 60, endMinuteOfDay: 14 * 60)
        ]
        #expect(TimeWindowPolicy.firstInvalidReason(for: contiguous) == nil)
    }

    @Test func timeWindowPolicyAcceptsUnsortedValidWindows() {
        let windows = [
            TimeWindow(startMinuteOfDay: 13 * 60, endMinuteOfDay: 18 * 60),
            TimeWindow(startMinuteOfDay: 10 * 60, endMinuteOfDay: 12 * 60)
        ]
        #expect(TimeWindowPolicy.firstInvalidReason(for: windows) == nil)
    }

    @Test func isInsideAnyWindowAndActiveWindowEnd() {
        let windows = [
            TimeWindow(startMinuteOfDay: 10 * 60, endMinuteOfDay: 12 * 60),
            TimeWindow(startMinuteOfDay: 13 * 60, endMinuteOfDay: 18 * 60)
        ]

        #expect(TimeWindowPolicy.isInsideAnyWindow(minuteOfDay: 11 * 60, windows: windows))
        #expect(!TimeWindowPolicy.isInsideAnyWindow(minuteOfDay: 12 * 60 + 30, windows: windows))
        #expect(TimeWindowPolicy.activeWindowEnd(minuteOfDay: 14 * 60, windows: windows) == 18 * 60)
        #expect(TimeWindowPolicy.activeWindowEnd(minuteOfDay: 9 * 60, windows: windows) == nil)
    }

    // MARK: - ScreenTimeGroup Codable 하위 호환

    /// 현재 그룹 인코딩에서 새 키만 제거해 1.0.x 페이로드를 재현한다.
    /// (구버전 저장 데이터의 selection도 sanitize를 거친 형태였으므로 이 방식이 실제와 같다.)
    private func legacyPayload(id: UUID, name: String, dailyLimitMinutes: Int) throws -> Data {
        let group = SharedStore.ScreenTimeGroup(id: id, name: name, dailyLimitMinutes: dailyLimitMinutes)
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(group)
        ) as! [String: Any]
        json.removeValue(forKey: "isApplied")
        json.removeValue(forKey: "ruleKind")
        json.removeValue(forKey: "timeWindows")
        return try JSONSerialization.data(withJSONObject: json)
    }

    @Test func legacyGroupPayloadDecodesAsAppliedDailyLimit() throws {
        // 1.0.x 페이로드(새 키 없음)는 일일 한도 규칙이 이미 적용된 그룹으로 디코딩된다.
        let id = UUID()
        let payload = try legacyPayload(id: id, name: "게임", dailyLimitMinutes: 45)

        let group = try JSONDecoder().decode(SharedStore.ScreenTimeGroup.self, from: payload)

        #expect(group.id == id)
        #expect(group.dailyLimitMinutes == 45)
        #expect(group.isApplied == true)
        #expect(group.ruleKind == .dailyLimit)
        #expect(group.timeWindows.isEmpty)
    }

    @Test func legacyGroupPayloadEqualsDefaultInitGroup() throws {
        // 업데이트 직후 lastRegisteredGroupsByID(구버전 인코딩)와 현재 그룹이 Equatable로 일치해야
        // syncDailyMonitoring이 불필요한 재등록(daily 카운터 리셋)을 하지 않는다.
        let id = UUID()
        let payload = try legacyPayload(id: id, name: "게임", dailyLimitMinutes: 45)
        let decoded = try JSONDecoder().decode(SharedStore.ScreenTimeGroup.self, from: payload)

        let constructed = SharedStore.ScreenTimeGroup(id: id, name: "게임", dailyLimitMinutes: 45)

        #expect(decoded == constructed)
    }

    @Test func unknownRuleKindFallsBackToDailyLimit() throws {
        // 미래 버전이 추가한 규칙 값을 만나도 보호가 끊기지 않도록 일일 한도로 fallback.
        let selectionJSON = String(
            data: try JSONEncoder().encode(FamilyActivitySelection()),
            encoding: .utf8
        )!
        let payload = Data("""
        {
            "id": "\(UUID().uuidString)",
            "name": "게임",
            "selection": \(selectionJSON),
            "dailyLimitMinutes": 30,
            "isApplied": true,
            "ruleKind": "weeklyLimit",
            "timeWindows": []
        }
        """.utf8)

        let group = try JSONDecoder().decode(SharedStore.ScreenTimeGroup.self, from: payload)

        #expect(group.ruleKind == .dailyLimit)
        #expect(group.isApplied == true)
    }

    @Test func draftGroupRoundTripsThroughCodable() throws {
        // 신형 페이로드에서 ruleKind nil(규칙 미선택 draft)은 디코딩 후에도 nil로 보존된다.
        let draft = SharedStore.ScreenTimeGroup(
            name: "새 그룹",
            ruleKind: nil,
            isApplied: false
        )

        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(SharedStore.ScreenTimeGroup.self, from: data)

        #expect(decoded.ruleKind == nil)
        #expect(decoded.isApplied == false)
        #expect(decoded == draft)
    }

    @Test func timeWindowGroupRoundTripsThroughCodable() throws {
        let windows = [
            TimeWindow(startMinuteOfDay: 10 * 60, endMinuteOfDay: 12 * 60),
            TimeWindow(startMinuteOfDay: 13 * 60, endMinuteOfDay: 18 * 60)
        ]
        let group = SharedStore.ScreenTimeGroup(
            name: "공부 시간",
            ruleKind: .timeWindows,
            timeWindows: windows,
            isApplied: true
        )

        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(SharedStore.ScreenTimeGroup.self, from: data)

        #expect(decoded.ruleKind == .timeWindows)
        #expect(decoded.timeWindows == windows)
        #expect(decoded == group)
    }

    // MARK: - ScreenTimeGroupPolicy 규칙 분기

    @Test func groupPolicyRejectsGroupWithoutRule() {
        let groups = [
            ScreenTimeGroupPolicy.GroupSnapshot(
                name: "새 그룹",
                appTokens: ["app-1"],
                dailyLimitMinutes: 30,
                ruleKind: nil
            )
        ]

        #expect(ScreenTimeGroupPolicy.firstInvalidReason(for: groups) == .groupHasNoRule("새 그룹"))
    }

    @Test func groupPolicyValidatesTimeWindowsRule() {
        let overlapping = [
            ScreenTimeGroupPolicy.GroupSnapshot(
                name: "공부 시간",
                appTokens: ["app-1"],
                dailyLimitMinutes: 30,
                ruleKind: .timeWindows,
                timeWindows: [
                    TimeWindow(startMinuteOfDay: 600, endMinuteOfDay: 720),
                    TimeWindow(startMinuteOfDay: 700, endMinuteOfDay: 780)
                ]
            )
        ]
        #expect(
            ScreenTimeGroupPolicy.firstInvalidReason(for: overlapping)
                == .groupHasInvalidTimeWindows("공부 시간", .overlapping)
        )

        // 시간대 규칙 그룹은 dailyLimitMinutes 값과 무관하게 시간대만 유효하면 통과한다.
        let valid = [
            ScreenTimeGroupPolicy.GroupSnapshot(
                name: "공부 시간",
                appTokens: ["app-1"],
                dailyLimitMinutes: -1,
                ruleKind: .timeWindows,
                timeWindows: [TimeWindow(startMinuteOfDay: 600, endMinuteOfDay: 720)]
            )
        ]
        #expect(ScreenTimeGroupPolicy.firstInvalidReason(for: valid) == nil)
    }

    // MARK: - resyncTimeWindowLocks (모니터링 엔진)

    private func makeWindowGroup(
        id: UUID = UUID(),
        windows: [SharedStore.TimeWindow],
        isApplied: Bool = true
    ) -> SharedStore.ScreenTimeGroup {
        SharedStore.ScreenTimeGroup(
            id: id,
            name: "시간대 그룹",
            ruleKind: .timeWindows,
            timeWindows: windows,
            isApplied: isApplied
        )
    }

    private func date(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 6, day: 13, hour: hour, minute: minute)
        )!
    }

    @Test func resyncLocksGroupInsideWindowThenIdempotent() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let id = UUID()
        SharedStore.screenTimeGroups = [
            makeWindowGroup(id: id, windows: [TimeWindow(startMinuteOfDay: 600, endMinuteOfDay: 720)])
        ]

        let first = SharedStore.resyncTimeWindowLocks(now: date(11, 0))
        #expect(first.changed)
        #expect(first.newlyLocked.contains(id))
        #expect(SharedStore.shieldedGroupIDs.contains(id))

        // 같은 시각으로 다시 호출하면 멤버십 변화가 없으므로 changed == false.
        let second = SharedStore.resyncTimeWindowLocks(now: date(11, 0))
        #expect(!second.changed)
        #expect(second.newlyLocked.isEmpty)
        #expect(SharedStore.shieldedGroupIDs.contains(id))
    }

    @Test func resyncUnlocksGroupOutsideWindow() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let id = UUID()
        SharedStore.screenTimeGroups = [
            makeWindowGroup(id: id, windows: [TimeWindow(startMinuteOfDay: 600, endMinuteOfDay: 720)])
        ]
        SharedStore.markGroupShielded(id)

        let result = SharedStore.resyncTimeWindowLocks(now: date(13, 0))
        #expect(result.changed)
        #expect(!SharedStore.shieldedGroupIDs.contains(id))
    }

    @Test func resyncBoundaryIsBothInclusive() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let id = UUID()
        // 10:00–11:59(inclusive) 차단 시간대.
        SharedStore.screenTimeGroups = [
            makeWindowGroup(id: id, windows: [TimeWindow(startMinuteOfDay: 600, endMinuteOfDay: 719)])
        ]

        // 시작 정각(10:00) 포함 → 잠금.
        _ = SharedStore.resyncTimeWindowLocks(now: date(10, 0))
        #expect(SharedStore.shieldedGroupIDs.contains(id))

        // 종료 분(11:59) 포함 → 계속 잠금.
        let atEnd = SharedStore.resyncTimeWindowLocks(now: date(11, 59))
        #expect(!atEnd.changed)
        #expect(SharedStore.shieldedGroupIDs.contains(id))

        // 종료 다음 분(12:00) 미포함 → 해제.
        let after = SharedStore.resyncTimeWindowLocks(now: date(12, 0))
        #expect(after.changed)
        #expect(!SharedStore.shieldedGroupIDs.contains(id))
    }

    @Test func resyncLeavesDailyLimitGroupUntouched() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let dailyID = UUID()
        SharedStore.screenTimeGroups = [
            SharedStore.ScreenTimeGroup(id: dailyID, name: "게임", dailyLimitMinutes: 30)
        ]
        SharedStore.markGroupShielded(dailyID)

        // 시간대 그룹이 아니므로 어떤 시각이든 멤버십이 유지된다.
        let result = SharedStore.resyncTimeWindowLocks(now: date(3, 0))
        #expect(!result.changed)
        #expect(SharedStore.shieldedGroupIDs.contains(dailyID))
    }

    @Test func resyncIgnoresDraftWindowGroup() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let id = UUID()
        SharedStore.screenTimeGroups = [
            makeWindowGroup(
                id: id,
                windows: [TimeWindow(startMinuteOfDay: 600, endMinuteOfDay: 720)],
                isApplied: false
            )
        ]

        let result = SharedStore.resyncTimeWindowLocks(now: date(11, 0))
        #expect(!result.changed)
        #expect(!SharedStore.shieldedGroupIDs.contains(id))
    }

    @Test func resyncKeepsLockAcrossContiguousWindowBoundary() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let id = UUID()
        // 10:00–11:59 + 12:00–12:59 연속(end+1 == next.start) → 경계에서 끊김 없이 잠금.
        SharedStore.screenTimeGroups = [
            makeWindowGroup(id: id, windows: [
                TimeWindow(startMinuteOfDay: 10 * 60, endMinuteOfDay: 12 * 60 - 1),
                TimeWindow(startMinuteOfDay: 12 * 60, endMinuteOfDay: 13 * 60 - 1)
            ])
        ]

        // 11:59는 첫 시간대 종료(포함), 12:00은 둘째 시간대 시작(포함) → 경계 넘어도 잠금 유지.
        _ = SharedStore.resyncTimeWindowLocks(now: date(11, 30))
        #expect(SharedStore.shieldedGroupIDs.contains(id))
        let atBoundary = SharedStore.resyncTimeWindowLocks(now: date(12, 0))
        #expect(!atBoundary.changed)
        #expect(SharedStore.shieldedGroupIDs.contains(id))
    }

    @Test func resyncWithOverrideKeepsMarkButExcludesFromLocked() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let id = UUID()
        SharedStore.screenTimeGroups = [
            makeWindowGroup(id: id, windows: [TimeWindow(startMinuteOfDay: 600, endMinuteOfDay: 720)])
        ]

        let now = date(11, 0)
        SharedStore.setOverride(until: now.addingTimeInterval(15 * 60), for: id)

        // 시간대 안 + override 중: marked는 유지하되 lockedGroups에는 없다.
        _ = SharedStore.resyncTimeWindowLocks(now: now)
        #expect(SharedStore.shieldedGroupIDs.contains(id))
        #expect(!SharedStore.lockedGroups(now: now).contains { $0.id == id })

        // 시간대 밖이면 override 여부와 무관하게 unmark.
        let outside = date(13, 0)
        let result = SharedStore.resyncTimeWindowLocks(now: outside)
        #expect(result.changed)
        #expect(!SharedStore.shieldedGroupIDs.contains(id))
    }

    // MARK: - DeviceActivityName.timeWindow round-trip

    @Test func timeWindowActivityNameParsesGroupID() {
        let id = UUID()
        let name = DeviceActivityName.timeWindow(for: id, index: 2)
        #expect(name.rawValue == "window.\(id.uuidString).2")
        #expect(name.timeWindowGroupID == id)

        // daily/override 이름은 시간대 파서에 잡히지 않는다.
        #expect(DeviceActivityName.override(for: id).timeWindowGroupID == nil)
        #expect(DeviceActivityName.dailyGroup(for: id, generation: 0).timeWindowGroupID == nil)
    }
}
