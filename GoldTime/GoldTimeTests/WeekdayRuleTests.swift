//
//  WeekdayRuleTests.swift
//  GoldTimeTests
//
//  요일별 제한 규칙 데이터 모델(DayRule / ScreenTimeGroup.weekdayRules)의 Codable 하위 호환 검증.
//  never-throw 원칙(배열 요소·그룹 1개 실패가 전체 소실로 이어지지 않음)에 초점을 둔다.
//

import Testing
import Foundation
import DeviceActivity
import FamilyControls
@testable import GoldTime

@MainActor
struct WeekdayRuleTests {

    // MARK: - 헬퍼

    /// 다양한 kind가 섞인 7요일 규칙(0=일 … 6=토).
    private func sampleWeekdayRules() -> [SharedStore.DayRule] {
        [
            SharedStore.DayRule(kind: .unrestricted),
            SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 45),
            SharedStore.DayRule(kind: .timeWindows, timeWindows: [
                TimeWindow(startMinuteOfDay: 9 * 60, endMinuteOfDay: 12 * 60)
            ]),
            SharedStore.DayRule(kind: .cooldown, cooldownUsageMinutes: 20, cooldownDurationMinutes: 60),
            SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 90),
            SharedStore.DayRule(kind: .unrestricted),
            SharedStore.DayRule(kind: .timeWindows, timeWindows: [
                TimeWindow(startMinuteOfDay: 20 * 60, endMinuteOfDay: 22 * 60)
            ])
        ]
    }

    /// 그룹을 JSON dict로 인코딩한다. FamilyActivitySelection JSON을 손으로 쓰지 않고
    /// 실제 인코딩 결과를 템플릿으로 삼아 부분만 조작하기 위한 헬퍼(기존 legacyPayload 패턴).
    private func jsonObject(from group: SharedStore.ScreenTimeGroup) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(group)) as! [String: Any]
    }

    // MARK: - 1. 왕복

    @Test func weekdayRulesRoundTripPreservesAllFields() throws {
        // 다양한 kind가 섞인 7요일 규칙을 가진 그룹은 인코딩→디코딩 후 전 필드가 보존된다.
        let rules = sampleWeekdayRules()
        let group = SharedStore.ScreenTimeGroup(
            name: "요일별 그룹",
            ruleKind: .dailyLimit,
            isApplied: true,
            weekdayRules: rules
        )

        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(SharedStore.ScreenTimeGroup.self, from: data)

        #expect(decoded.weekdayRules == rules)
        #expect(decoded.weekdayRules?.count == 7)
        #expect(decoded == group)
    }

    // MARK: - 2. 구버전 페이로드(isApplied 키 없음)

    @Test func legacyPayloadHasNilWeekdayRules() throws {
        // 1.0.x 페이로드(isApplied/신규 키 없음)는 weekdayRules == nil + 기존 폴백(일일 한도·적용됨)을 유지한다.
        let base = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임", dailyLimitMinutes: 45)
        var json = try jsonObject(from: base)
        json.removeValue(forKey: "isApplied")
        json.removeValue(forKey: "ruleKind")
        json.removeValue(forKey: "timeWindows")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(SharedStore.ScreenTimeGroup.self, from: data)

        #expect(decoded.weekdayRules == nil)
        #expect(decoded.isApplied == true)
        #expect(decoded.ruleKind == .dailyLimit)
    }

    // MARK: - 3. weekdayRules 키 부재(현행 1.1.x 신형 페이로드)

    @Test func currentPayloadWithoutWeekdayRulesKeyDecodesAsNil() throws {
        // weekdayRules를 쓰지 않는 현행 그룹은 디코딩 성공 + weekdayRules == nil.
        let group = SharedStore.ScreenTimeGroup(name: "게임", ruleKind: .dailyLimit, isApplied: true)
        let data = try JSONEncoder().encode(group)

        let decoded = try JSONDecoder().decode(SharedStore.ScreenTimeGroup.self, from: data)

        #expect(decoded.weekdayRules == nil)
        #expect(decoded.ruleKind == .dailyLimit)
    }

    // MARK: - 4. 7개 미만/초과 배열

    @Test func nonSevenElementArrayDropsOnlyWeekdayRules() throws {
        // 배열 길이가 7이 아니면 weekdayRules만 nil로 버리고 그룹 나머지 필드는 정상 디코딩된다.
        let sixRules = Array(sampleWeekdayRules().prefix(6))
        let underGroup = SharedStore.ScreenTimeGroup(
            name: "게임", dailyLimitMinutes: 40, ruleKind: .dailyLimit, isApplied: true,
            weekdayRules: sixRules
        )
        let underData = try JSONEncoder().encode(underGroup)
        let underDecoded = try JSONDecoder().decode(SharedStore.ScreenTimeGroup.self, from: underData)
        #expect(underDecoded.weekdayRules == nil)
        #expect(underDecoded.dailyLimitMinutes == 40)
        #expect(underDecoded.ruleKind == .dailyLimit)
        #expect(underDecoded.isApplied == true)

        let eightRules = sampleWeekdayRules() + [SharedStore.DayRule(kind: .dailyLimit)]
        let overGroup = SharedStore.ScreenTimeGroup(
            name: "게임", dailyLimitMinutes: 40, ruleKind: .dailyLimit, isApplied: true,
            weekdayRules: eightRules
        )
        let overData = try JSONEncoder().encode(overGroup)
        let overDecoded = try JSONDecoder().decode(SharedStore.ScreenTimeGroup.self, from: overData)
        #expect(overDecoded.weekdayRules == nil)
        #expect(overDecoded.dailyLimitMinutes == 40)
    }

    // MARK: - 5. 미지 kind 문자열

    @Test func unknownKindInElementFallsBackButKeepsArray() throws {
        // 요소 1개의 kind가 미래 버전 값이어도 그 요소만 .dailyLimit로 폴백하고 배열은 7개를 유지한다.
        let group = SharedStore.ScreenTimeGroup(
            name: "게임", ruleKind: .dailyLimit, isApplied: true,
            weekdayRules: sampleWeekdayRules()
        )
        var json = try jsonObject(from: group)
        var rulesJSON = json["weekdayRules"] as! [[String: Any]]
        rulesJSON[0]["kind"] = "someFutureKind"  // 원래 .unrestricted였던 요소
        json["weekdayRules"] = rulesJSON
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(SharedStore.ScreenTimeGroup.self, from: data)

        #expect(decoded.weekdayRules?.count == 7)
        #expect(decoded.weekdayRules?[0].kind == .dailyLimit)  // 미지 값 → 폴백
        #expect(decoded.weekdayRules?[3].kind == .cooldown)    // 나머지 요소는 원본 보존
    }

    // MARK: - 6. encodeIfPresent 확인

    @Test func nilWeekdayRulesOmitsKeyInEncoding() throws {
        // weekdayRules == nil이면 인코딩 JSON에 키 자체가 없어야 구버전과 왕복이 안전하다.
        let group = SharedStore.ScreenTimeGroup(name: "게임", ruleKind: .dailyLimit, isApplied: true)
        #expect(group.weekdayRules == nil)

        let json = try jsonObject(from: group)
        #expect(json["weekdayRules"] == nil)
    }

    // MARK: - 7. DayRule 요소 손상(타입 불일치)

    @Test func corruptedElementKindDoesNotThrow() throws {
        // 요소의 kind에 문자열이 아닌 숫자가 들어와도 DayRule.init(from:)이 throw하지 않아
        // 배열 전체와 그룹이 살아남고, 손상 요소만 .dailyLimit로 폴백한다.
        let group = SharedStore.ScreenTimeGroup(
            name: "게임", dailyLimitMinutes: 33, ruleKind: .dailyLimit, isApplied: true,
            weekdayRules: sampleWeekdayRules()
        )
        var json = try jsonObject(from: group)
        var rulesJSON = json["weekdayRules"] as! [[String: Any]]
        rulesJSON[2]["kind"] = 123  // 문자열이어야 할 kind에 숫자
        json["weekdayRules"] = rulesJSON
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(SharedStore.ScreenTimeGroup.self, from: data)

        #expect(decoded.dailyLimitMinutes == 33)             // 그룹 필드 생존
        #expect(decoded.weekdayRules?.count == 7)            // 배열 전체 보존
        #expect(decoded.weekdayRules?[2].kind == .dailyLimit) // 손상 요소는 폴백
    }
}
