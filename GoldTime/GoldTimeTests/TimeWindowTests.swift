//
//  TimeWindowTests.swift
//  GoldTimeTests
//
//  시간대별 차단 규칙의 모델(Codable 하위 호환)과 순수 정책 검증.
//

import Testing
import Foundation
import FamilyControls
@testable import GoldTime

@MainActor
struct TimeWindowTests {

    // MARK: - TimeWindow 판정

    @Test func timeWindowContainsIsStartInclusiveEndExclusive() {
        let window = SharedStore.TimeWindow(startMinuteOfDay: 600, endMinuteOfDay: 720) // 10:00-12:00

        #expect(window.contains(minuteOfDay: 600))
        #expect(window.contains(minuteOfDay: 719))
        #expect(!window.contains(minuteOfDay: 599))
        #expect(!window.contains(minuteOfDay: 720))
        #expect(window.durationMinutes == 120)
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
        // 22:00-02:00처럼 start >= end는 자정 넘김으로 본다.
        let crossing = [TimeWindow(startMinuteOfDay: 22 * 60, endMinuteOfDay: 2 * 60)]
        #expect(TimeWindowPolicy.firstInvalidReason(for: crossing) == .crossesMidnight)

        let zeroLength = [TimeWindow(startMinuteOfDay: 600, endMinuteOfDay: 600)]
        #expect(TimeWindowPolicy.firstInvalidReason(for: zeroLength) == .crossesMidnight)

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

    @Test func timeWindowPolicyRejectsOverlapButAllowsTouching() {
        let overlapping = [
            TimeWindow(startMinuteOfDay: 600, endMinuteOfDay: 720),
            TimeWindow(startMinuteOfDay: 700, endMinuteOfDay: 780)
        ]
        #expect(TimeWindowPolicy.firstInvalidReason(for: overlapping) == .overlapping)

        // 12:00 종료 + 12:00 시작처럼 맞닿은 시간대는 허용 (contains가 end 미포함이라 중복 잠금 없음).
        let touching = [
            TimeWindow(startMinuteOfDay: 600, endMinuteOfDay: 720),
            TimeWindow(startMinuteOfDay: 720, endMinuteOfDay: 18 * 60)
        ]
        #expect(TimeWindowPolicy.firstInvalidReason(for: touching) == nil)
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
}
