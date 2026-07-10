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

/// WeekdayRulePolicy(검증·요일 인덱스)와 resolved(on:) 투영의 순수 로직 검증.
@MainActor
struct WeekdayRulePolicyTests {

    // MARK: - 헬퍼

    /// 시간대 고정 그레고리력(테스트 결정성). 2026-07-05(일)~07-11(토)이 index 0~6에 대응한다.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// index마다 일일 한도가 다른(10+index) 7요일 규칙 — 투영 매핑 검증용.
    private func indexedRules() -> [SharedStore.DayRule] {
        (0..<7).map { SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 10 + $0) }
    }

    // MARK: - weekdayIndex / displayOrderedIndices

    @Test func weekdayIndexIsStableAcrossFirstWeekday() {
        // Calendar.weekday는 firstWeekday 설정과 무관하게 1=일요일 고정이다.
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        let sunday = date(2026, 7, 5)
        #expect(WeekdayRulePolicy.weekdayIndex(for: sunday, calendar: calendar) == 0)
        #expect(WeekdayRulePolicy.weekdayIndex(for: sunday, calendar: mondayFirst) == 0)
        #expect(WeekdayRulePolicy.weekdayIndex(for: date(2026, 7, 11), calendar: mondayFirst) == 6)
    }

    @Test func displayOrderedIndicesRotateByWeekStartDay() {
        #expect(WeekdayRulePolicy.displayOrderedIndices(weekStartDay: 1) == [0, 1, 2, 3, 4, 5, 6])
        #expect(WeekdayRulePolicy.displayOrderedIndices(weekStartDay: 2) == [1, 2, 3, 4, 5, 6, 0])
        #expect(WeekdayRulePolicy.displayOrderedIndices(weekStartDay: 7) == [6, 0, 1, 2, 3, 4, 5])
        // 범위 밖 값은 월요일 시작으로 폴백(SharedStore.weekStartDay 기본값 2와 동일).
        #expect(WeekdayRulePolicy.displayOrderedIndices(weekStartDay: 0) == [1, 2, 3, 4, 5, 6, 0])
        #expect(WeekdayRulePolicy.displayOrderedIndices(weekStartDay: 8) == [1, 2, 3, 4, 5, 6, 0])
    }

    // MARK: - resolved(on:) 투영

    @Test func resolvedProjectsEachWeekdayAndStripsRules() {
        // 한 주(일~토)의 각 날짜가 해당 index의 DayRule로 투영되고, 투영본은 weekdayRules가 nil이다.
        let group = SharedStore.ScreenTimeGroup(
            name: "SNS", ruleKind: .cooldown, isApplied: true, weekdayRules: indexedRules()
        )
        for offset in 0..<7 {
            let projected = group.resolved(on: date(2026, 7, 5 + offset), calendar: calendar)
            #expect(projected.ruleKind == .dailyLimit)
            #expect(projected.dailyLimitMinutes == 10 + offset)
            #expect(projected.weekdayRules == nil)
        }
    }

    @Test func resolvedMapsKindAndCopiesAllParams() {
        let windows = [TimeWindow(startMinuteOfDay: 540, endMinuteOfDay: 719)]
        var rules = indexedRules()
        rules[0] = SharedStore.DayRule(kind: .unrestricted)
        rules[2] = SharedStore.DayRule(kind: .timeWindows, timeWindows: windows)
        rules[4] = SharedStore.DayRule(kind: .cooldown, cooldownUsageMinutes: 25, cooldownDurationMinutes: 90)
        let group = SharedStore.ScreenTimeGroup(
            name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true, weekdayRules: rules
        )

        // 일요일: 제한 없음 → ruleKind nil(기존 정책이 모니터링에서 자연 제외).
        let sunday = group.resolved(on: date(2026, 7, 5), calendar: calendar)
        #expect(sunday.ruleKind == nil)
        // 화요일: 시간대 — windows 복사.
        let tuesday = group.resolved(on: date(2026, 7, 7), calendar: calendar)
        #expect(tuesday.ruleKind == .timeWindows)
        #expect(tuesday.timeWindows == windows)
        // 목요일: 쿨다운 — 파라미터 2개 복사.
        let thursday = group.resolved(on: date(2026, 7, 9), calendar: calendar)
        #expect(thursday.ruleKind == .cooldown)
        #expect(thursday.cooldownUsageMinutes == 25)
        #expect(thursday.cooldownDurationMinutes == 90)
    }

    @Test func resolvedIsPassthroughForNonWeekdayGroup() {
        let group = SharedStore.ScreenTimeGroup(name: "SNS", ruleKind: .dailyLimit, isApplied: true)
        #expect(group.resolved(on: date(2026, 7, 5), calendar: calendar) == group)
    }

    @Test func resolvedTreatsMalformedCountAsBaseRule() {
        // 7개가 아닌 비정상 배열은 디코더 폴백과 동일하게 base 규칙 취급(weekdayRules만 스트립).
        let group = SharedStore.ScreenTimeGroup(
            name: "SNS", dailyLimitMinutes: 55, ruleKind: .dailyLimit, isApplied: true,
            weekdayRules: Array(indexedRules().prefix(3))
        )
        let projected = group.resolved(on: date(2026, 7, 5), calendar: calendar)
        #expect(projected.ruleKind == .dailyLimit)
        #expect(projected.dailyLimitMinutes == 55)
        #expect(projected.weekdayRules == nil)
    }

    @Test func isUnrestrictedOnMatchesWeekday() {
        var rules = indexedRules()
        rules[6] = SharedStore.DayRule(kind: .unrestricted)
        let group = SharedStore.ScreenTimeGroup(
            name: "SNS", ruleKind: .dailyLimit, isApplied: true, weekdayRules: rules
        )
        #expect(group.isUnrestricted(on: date(2026, 7, 11), calendar: calendar))   // 토
        #expect(!group.isUnrestricted(on: date(2026, 7, 10), calendar: calendar))  // 금
        let plainGroup = SharedStore.ScreenTimeGroup(name: "SNS", ruleKind: .dailyLimit, isApplied: true)
        #expect(!plainGroup.isUnrestricted(on: date(2026, 7, 11), calendar: calendar))
    }

    // MARK: - firstInvalidReason

    @Test func firstInvalidReasonRejectsWrongCountAndAllUnrestricted() {
        #expect(WeekdayRulePolicy.firstInvalidReason(for: Array(indexedRules().prefix(6))) == .wrongDayCount)
        let allOff = (0..<7).map { _ in SharedStore.DayRule(kind: .unrestricted) }
        #expect(WeekdayRulePolicy.firstInvalidReason(for: allOff) == .allUnrestricted)
        #expect(WeekdayRulePolicy.firstInvalidReason(for: indexedRules()) == nil)
    }

    @Test func firstInvalidReasonDelegatesPerDayValidation() {
        // 화요일(index 2)에 겹치는 시간대 → 해당 요일의 timeWindow 사유.
        var overlapping = indexedRules()
        overlapping[2] = SharedStore.DayRule(kind: .timeWindows, timeWindows: [
            TimeWindow(startMinuteOfDay: 720, endMinuteOfDay: 780),
            TimeWindow(startMinuteOfDay: 780, endMinuteOfDay: 840)
        ])
        guard case .dayInvalid(let windowIndex, .timeWindow) = WeekdayRulePolicy.firstInvalidReason(for: overlapping) else {
            Issue.record("겹치는 시간대가 dayInvalid(.timeWindow)로 잡혀야 한다")
            return
        }
        #expect(windowIndex == 2)

        // 금요일(index 5)에 범위 밖 쿨다운 예산 → 해당 요일의 cooldown 사유.
        var badCooldown = indexedRules()
        badCooldown[5] = SharedStore.DayRule(kind: .cooldown, cooldownUsageMinutes: 0)
        guard case .dayInvalid(let cooldownIndex, .cooldown) = WeekdayRulePolicy.firstInvalidReason(for: badCooldown) else {
            Issue.record("범위 밖 쿨다운이 dayInvalid(.cooldown)로 잡혀야 한다")
            return
        }
        #expect(cooldownIndex == 5)

        // 수요일(index 3)에 음수 일일 한도 → dailyLimit 사유.
        var badLimit = indexedRules()
        badLimit[3] = SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: -1)
        #expect(WeekdayRulePolicy.firstInvalidReason(for: badLimit) == .dayInvalid(weekdayIndex: 3, .dailyLimit))
    }

    // MARK: - ruleInvalidReason 요일 분기

    @Test func ruleInvalidReasonAcceptsValidWeekdayRulesWithoutBaseKind() {
        // 요일별 모드에서는 base ruleKind가 nil(미선택)이어도 유효 — 요일 규칙 자체가 규칙 선택.
        let valid = ScreenTimeGroupPolicy.GroupSnapshot<String>(
            name: "SNS", appTokens: ["a"], dailyLimitMinutes: 30,
            ruleKind: nil, weekdayRules: indexedRules()
        )
        #expect(ScreenTimeGroupPolicy.ruleInvalidReason(for: valid) == nil)

        var badRules = indexedRules()
        badRules[1] = SharedStore.DayRule(kind: .cooldown, cooldownUsageMinutes: 0)
        let invalid = ScreenTimeGroupPolicy.GroupSnapshot<String>(
            name: "SNS", appTokens: ["a"], dailyLimitMinutes: 30,
            ruleKind: .dailyLimit, weekdayRules: badRules
        )
        guard case .groupHasInvalidWeekdayRules = ScreenTimeGroupPolicy.ruleInvalidReason(for: invalid) else {
            Issue.record("무효 요일 규칙이 groupHasInvalidWeekdayRules로 잡혀야 한다")
            return
        }

        // 비요일 그룹의 기존 동작 회귀: 규칙 미선택은 여전히 draft 취급.
        let draft = ScreenTimeGroupPolicy.GroupSnapshot<String>(
            name: "SNS", appTokens: ["a"], dailyLimitMinutes: 30, ruleKind: nil
        )
        #expect(ScreenTimeGroupPolicy.ruleInvalidReason(for: draft) == .groupHasNoRule("SNS"))
    }

    // MARK: - 투영 churn (등록 재시작 판정)

    @Test func projectionEqualityDetectsOnlyTodayRuleEdits() {
        // syncDailyMonitoring/heartbeat의 churn 가드 `last != group`은 투영본끼리 비교한다.
        // 같은 id·selection을 유지한 채 오늘(일=index 0) 외 요일만 편집하면 오늘 투영본이 동일 →
        // 재시작 없음. 오늘 요일을 편집하면 투영본이 달라져 재시작이 일어난다.
        let sunday = date(2026, 7, 5)   // index 0
        let id = UUID()
        func projection(_ rules: [SharedStore.DayRule]) -> SharedStore.ScreenTimeGroup {
            SharedStore.ScreenTimeGroup(
                id: id, name: "SNS", ruleKind: .dailyLimit, isApplied: true, weekdayRules: rules
            ).resolved(on: sunday, calendar: calendar)
        }

        let base = projection(indexedRules())

        var otherDayEdited = indexedRules()
        otherDayEdited[3] = SharedStore.DayRule(kind: .cooldown, cooldownUsageMinutes: 20, cooldownDurationMinutes: 60)
        #expect(projection(otherDayEdited) == base)   // 오늘 규칙 불변 → churn 없음

        var todayEdited = indexedRules()
        todayEdited[0] = SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 999)
        #expect(projection(todayEdited) != base)      // 오늘 규칙 변경 → churn
    }
}

/// 3단계 등록/자정 전환 코어(needsHeartbeat 요일 확장, resyncTimeWindowLocks 요일 게이트,
/// pruneShieldState 이원화)의 순수/SharedStore 로직 검증.
@MainActor
struct WeekdayRuleEngineTests {

    private func indexedRules() -> [SharedStore.DayRule] {
        (0..<7).map { SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 10 + $0) }
    }

    // MARK: - needsHeartbeat 요일 확장

    @Test func heartbeatNeededForAppliedWeekdayGroupEvenWithoutValidToday() {
        let weekday = SharedStore.ScreenTimeGroup(
            name: "요일", ruleKind: nil, isApplied: true, weekdayRules: indexedRules()
        )
        let weekdayDraft = SharedStore.ScreenTimeGroup(
            name: "요일", ruleKind: nil, isApplied: false, weekdayRules: indexedRules()
        )
        let plainWindow = SharedStore.ScreenTimeGroup(name: "시간대", ruleKind: .timeWindows, isApplied: true)
        let plainDaily = SharedStore.ScreenTimeGroup(name: "일일", ruleKind: .dailyLimit, isApplied: true)

        // 적용된 요일 그룹은 오늘 유효 그룹이 없어도(오늘 전부 '제한 없음' 등) 하트비트를 유지한다.
        #expect(DailyMonitor.needsHeartbeat(for: [], appliedGroups: [weekday]))
        // 미적용(draft) 요일 그룹은 아직 하트비트가 불필요하다.
        #expect(!DailyMonitor.needsHeartbeat(for: [], appliedGroups: [weekdayDraft]))
        // 비요일 시간대-only는 기존대로 불필요(회귀).
        #expect(!DailyMonitor.needsHeartbeat(for: [plainWindow], appliedGroups: [plainWindow]))
        // 오늘 daily/cooldown 유효 그룹이 있으면 기존대로 필요(회귀).
        #expect(DailyMonitor.needsHeartbeat(for: [plainDaily], appliedGroups: [plainDaily]))
    }

    // MARK: - resyncTimeWindowLocks 요일 게이트

    @Test func resyncTimeWindowLocksGatesOnTodayRule() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        // 실행일이 어떤 요일이든 결정적으로 만들기 위해 '오늘'의 요일 index를 계산해 그 슬롯만 조작한다.
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: Date())!
        let todayIndex = WeekdayRulePolicy.weekdayIndex(for: now)
        let window = SharedStore.DayRule(kind: .timeWindows, timeWindows: [
            TimeWindow(startMinuteOfDay: 600, endMinuteOfDay: 720)   // 10:00–12:00, now(11:00)는 창 안
        ])
        let daily = SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 30)

        // A: 오늘 = 시간대, 나머지 요일 = 일일 → 잠금돼야 한다.
        var rulesA = Array(repeating: daily, count: 7)
        rulesA[todayIndex] = window
        // B: 오늘 = 일일, 나머지 요일 = 같은 시간대 → 오늘이 시간대 규칙이 아니므로 무시(잠금 없음).
        var rulesB = Array(repeating: window, count: 7)
        rulesB[todayIndex] = daily

        let idA = UUID()
        let idB = UUID()
        SharedStore.screenTimeGroups = [
            SharedStore.ScreenTimeGroup(id: idA, name: "A", ruleKind: .dailyLimit, isApplied: true, weekdayRules: rulesA),
            SharedStore.ScreenTimeGroup(id: idB, name: "B", ruleKind: .dailyLimit, isApplied: true, weekdayRules: rulesB)
        ]

        let result = SharedStore.resyncTimeWindowLocks(now: now)
        #expect(result.newlyLocked.contains(idA))
        #expect(SharedStore.shieldedGroupIDs.contains(idA))
        #expect(!SharedStore.shieldedGroupIDs.contains(idB))
    }

    // MARK: - pruneShieldState 이원화

    @Test func pruneShieldStatePreservesCooldownGenerationForExistingGroup() {
        SharedStore.clearGroupStateForTesting()
        defer { SharedStore.clearGroupStateForTesting() }

        let unrestrictedTodayID = UUID()   // 존재하지만 오늘 유효하지 않은(제한 없음) 요일 그룹
        let deletedID = UUID()             // 삭제된 그룹

        SharedStore.cooldownGenerationByID = [unrestrictedTodayID: 3, deletedID: 5]
        SharedStore.cooldownBaselineByGroupID = [unrestrictedTodayID: 7, deletedID: 9]
        SharedStore.startCooldown(until: Date().addingTimeInterval(60), for: unrestrictedTodayID)

        // 첫 set(오늘 유효)은 비우고, 둘째 set(존재하는 그룹 전체)에는 unrestrictedTodayID를 유지한다.
        _ = SharedStore.pruneShieldState(
            keepingGroupIDs: [],
            keepingCooldownProgressGroupIDs: [unrestrictedTodayID]
        )

        // shield/cooldownUntil은 첫 set 기준 → unrestrictedTodayID도 비워진다(오늘은 앱 열림).
        #expect(SharedStore.cooldownUntilByGroupID[unrestrictedTodayID] == nil)
        #expect(!SharedStore.shieldedGroupIDs.contains(unrestrictedTodayID))
        // generation/baseline은 둘째 set 기준 → 보존(다음 등록의 gen 0 재사용·카운터 승계 회귀 방지).
        #expect(SharedStore.cooldownGenerationByID[unrestrictedTodayID] == 3)
        #expect(SharedStore.cooldownBaselineByGroupID[unrestrictedTodayID] == 7)
        // 삭제 그룹(둘째 set에도 없음)은 gen/baseline까지 제거.
        #expect(SharedStore.cooldownGenerationByID[deletedID] == nil)
        #expect(SharedStore.cooldownBaselineByGroupID[deletedID] == nil)
    }
}
