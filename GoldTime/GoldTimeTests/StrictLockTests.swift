//
//  StrictLockTests.swift
//  GoldTimeTests
//
//  금고 모드(기간 약정 강력 잠금) 데이터 모델(ScreenTimeGroup.strictUntil/strictStartedAt)의
//  Codable 하위 호환·약정 판정·만료 계산·resolved(on:) 투영 스트립을 검증한다.
//  never-throw 원칙(구버전 페이로드가 그룹 전체 소실로 이어지지 않음)에 초점을 둔다.
//

import Testing
import Foundation
import FamilyControls
@testable import GoldTime

@MainActor
struct StrictLockTests {

    // MARK: - 헬퍼

    /// 시간대 고정 그레고리력(테스트 결정성). 자정 경계 계산이 실행 지역/DST에 흔들리지 않게 한다.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// index마다 일일 한도가 다른(10+index) 7요일 규칙 — 투영 매핑 검증용.
    private func indexedRules() -> [SharedStore.DayRule] {
        (0..<7).map { SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 10 + $0) }
    }

    /// 그룹을 JSON dict로 인코딩한다(부분 조작용, WeekdayRuleTests와 동일 패턴).
    private func jsonObject(from group: SharedStore.ScreenTimeGroup) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(group)) as! [String: Any]
    }

    // MARK: - 1. 왕복

    @Test func strictFieldsRoundTripPreserved() throws {
        // strictUntil/strictStartedAt를 가진 그룹은 인코딩→디코딩 후 두 필드가 그대로 보존된다.
        let until = date(2026, 7, 15, 0, 0)
        let startedAt = date(2026, 7, 12, 14, 30)
        let group = SharedStore.ScreenTimeGroup(
            name: "게임", ruleKind: .dailyLimit, isApplied: true,
            strictUntil: until, strictStartedAt: startedAt
        )

        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(SharedStore.ScreenTimeGroup.self, from: data)

        #expect(decoded.strictUntil == until)
        #expect(decoded.strictStartedAt == startedAt)
        #expect(decoded == group)
    }

    // MARK: - 2. 하위 호환(strict 키 부재)

    @Test func payloadWithoutStrictKeysDecodesAsNilWithoutThrow() throws {
        // strict 키가 없는 페이로드는 두 필드 모두 nil로 디코딩되고 throw하지 않는다.
        // 신형(isApplied 있음)과 구버전(isApplied 없음) 두 분기 모두에서 nil이어야 한다.
        let base = SharedStore.ScreenTimeGroup(
            name: "게임", dailyLimitMinutes: 45, ruleKind: .dailyLimit, isApplied: true,
            strictUntil: date(2026, 7, 15, 0, 0), strictStartedAt: date(2026, 7, 12, 14, 30)
        )

        // (a) 신형 페이로드에서 strict 키만 제거.
        var modernJSON = try jsonObject(from: base)
        modernJSON.removeValue(forKey: "strictUntil")
        modernJSON.removeValue(forKey: "strictStartedAt")
        let modern = try JSONDecoder().decode(
            SharedStore.ScreenTimeGroup.self,
            from: try JSONSerialization.data(withJSONObject: modernJSON)
        )
        #expect(modern.strictUntil == nil)
        #expect(modern.strictStartedAt == nil)
        #expect(modern.isApplied == true)

        // (b) 구버전 페이로드(isApplied·신규 키 없음) — else 분기에서도 nil.
        var legacyJSON = try jsonObject(from: base)
        legacyJSON.removeValue(forKey: "strictUntil")
        legacyJSON.removeValue(forKey: "strictStartedAt")
        legacyJSON.removeValue(forKey: "isApplied")
        let legacy = try JSONDecoder().decode(
            SharedStore.ScreenTimeGroup.self,
            from: try JSONSerialization.data(withJSONObject: legacyJSON)
        )
        #expect(legacy.strictUntil == nil)
        #expect(legacy.strictStartedAt == nil)
        #expect(legacy.isApplied == true)          // 구버전 폴백: 적용됨
        #expect(legacy.ruleKind == .dailyLimit)    // 구버전 폴백: 일일 한도
    }

    // MARK: - 3. 인코딩 키 생략

    @Test func nilStrictFieldsOmitKeysInEncoding() throws {
        // nil이면 JSON에 strictUntil/strictStartedAt 키 자체가 없어 구버전과 바이트 왕복이 안전하다.
        let group = SharedStore.ScreenTimeGroup(name: "게임", ruleKind: .dailyLimit, isApplied: true)
        #expect(group.strictUntil == nil)
        #expect(group.strictStartedAt == nil)

        let json = try jsonObject(from: group)
        #expect(json["strictUntil"] == nil)
        #expect(json["strictStartedAt"] == nil)
    }

    // MARK: - 4. 약정 판정 경계

    @Test func isStrictLockActiveBoundary() {
        let now = date(2026, 7, 12, 14, 30)
        func group(_ until: Date?) -> SharedStore.ScreenTimeGroup {
            SharedStore.ScreenTimeGroup(name: "게임", ruleKind: .dailyLimit, isApplied: true, strictUntil: until)
        }
        // 정확히 만료 시각(strictUntil == now) → 비활성(판정은 strictUntil > now).
        #expect(!group(now).isStrictLockActive(at: now))
        // now 직전(1초 전 만료) → 비활성.
        #expect(!group(now.addingTimeInterval(-1)).isStrictLockActive(at: now))
        // now+1초 → 활성.
        #expect(group(now.addingTimeInterval(1)).isStrictLockActive(at: now))
        // nil(무약정) → 비활성.
        #expect(!group(nil).isStrictLockActive(at: now))
    }

    // MARK: - 5. 만료 시각 계산

    @Test func strictLockExpiryLandsOnNextMidnight() {
        // 임의 낮 시각 기준 만료는 항상 자정 0시 경계. days=1 → 다음날 00:00, days=3 → 3일 뒤 00:00.
        let now = date(2026, 7, 12, 14, 30)
        #expect(
            SharedStore.ScreenTimeGroup.strictLockExpiry(days: 1, from: now, calendar: calendar)
                == date(2026, 7, 13, 0, 0)
        )
        #expect(
            SharedStore.ScreenTimeGroup.strictLockExpiry(days: 3, from: now, calendar: calendar)
                == date(2026, 7, 15, 0, 0)
        )
    }

    // MARK: - 6. resolved(on:) 투영에서 strict 스트립

    @Test func resolvedStripsStrictFieldsForBothGroupKinds() {
        let until = date(2026, 7, 15, 0, 0)
        let startedAt = date(2026, 7, 12, 14, 30)

        // 비요일 그룹: strict 스트립 + 나머지 필드 불변.
        let plain = SharedStore.ScreenTimeGroup(
            name: "게임", dailyLimitMinutes: 40, ruleKind: .dailyLimit, isApplied: true,
            strictUntil: until, strictStartedAt: startedAt
        )
        let plainProjected = plain.resolved(on: date(2026, 7, 12), calendar: calendar)
        #expect(plainProjected.strictUntil == nil)
        #expect(plainProjected.strictStartedAt == nil)
        #expect(plainProjected.ruleKind == .dailyLimit)
        #expect(plainProjected.dailyLimitMinutes == 40)

        // 요일 그룹: strict 스트립 + 오늘(index 0=일) 규칙 투영 불변.
        let weekday = SharedStore.ScreenTimeGroup(
            name: "게임", ruleKind: .dailyLimit, isApplied: true,
            weekdayRules: indexedRules(), strictUntil: until, strictStartedAt: startedAt
        )
        let sunday = weekday.resolved(on: date(2026, 7, 5), calendar: calendar)  // index 0
        #expect(sunday.strictUntil == nil)
        #expect(sunday.strictStartedAt == nil)
        #expect(sunday.weekdayRules == nil)
        #expect(sunday.ruleKind == .dailyLimit)
        #expect(sunday.dailyLimitMinutes == 10)  // index 0 규칙 반영
    }

    @Test func strictToggleDoesNotChangeProjection() {
        // 금고 켜기 전후(같은 그룹, strictUntil만 다름)의 투영본이 == → 불필요한 churn 없음.
        let id = UUID()

        // 비요일 그룹.
        func plainProjection(_ until: Date?) -> SharedStore.ScreenTimeGroup {
            SharedStore.ScreenTimeGroup(
                id: id, name: "게임", ruleKind: .dailyLimit, isApplied: true, strictUntil: until
            ).resolved(on: date(2026, 7, 12), calendar: calendar)
        }
        #expect(plainProjection(nil) == plainProjection(date(2026, 7, 15, 0, 0)))

        // 요일 그룹.
        func weekdayProjection(_ until: Date?) -> SharedStore.ScreenTimeGroup {
            SharedStore.ScreenTimeGroup(
                id: id, name: "게임", ruleKind: .dailyLimit, isApplied: true,
                weekdayRules: indexedRules(), strictUntil: until
            ).resolved(on: date(2026, 7, 5), calendar: calendar)
        }
        #expect(weekdayProjection(nil) == weekdayProjection(date(2026, 7, 20, 0, 0)))
    }
}
