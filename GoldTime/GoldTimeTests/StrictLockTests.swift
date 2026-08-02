//
//  StrictLockTests.swift
//  GoldTimeTests
//
//  연장 불가 모드(기간 강력 잠금) 데이터 모델(ScreenTimeGroup.strictUntil/strictStartedAt)의
//  Codable 하위 호환·연장 불가 기간 판정·만료 계산·resolved(on:) 투영 스트립을 검증한다.
//  never-throw 원칙(구버전 페이로드가 그룹 전체 소실로 이어지지 않음)에 초점을 둔다.
//

import Testing
import Foundation
import FamilyControls
import ManagedSettings
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

    /// 앱 토큰 1개를 가진 유효 선택. 실기기 없이 selectionCount>0 → invalidReason==nil을 만든다.
    /// 토큰 바이트는 opaque라 ManagedSettings에 실제 적용되진 않지만, 정책 판정엔 개수만 쓰인다
    /// (앱 토큰의 인코딩 형태 `{"data":"<base64>"}`를 크래프팅해 디코딩).
    private func validSelection() -> FamilyActivitySelection {
        let json = "{\"categoryTokens\":[],\"applicationTokens\":[{\"data\":\"AQID\"}],\"untokenizedWebDomainIdentifiers\":[],\"untokenizedApplicationIdentifiers\":[],\"untokenizedCategoryIdentifiers\":[],\"webDomainTokens\":[],\"includeEntireCategory\":false}"
        return try! JSONDecoder().decode(FamilyActivitySelection.self, from: Data(json.utf8))
    }

    /// 편집·삭제·연장 불가 모드 적용 방어를 검증할 ManageGroupsUseCase(순수 inout 조작이라 repo는 스텁).
    private func makeManageUseCase() -> ManageGroupsUseCase {
        ManageGroupsUseCase(
            groupRepository: StrictFakeGroupRepository(),
            screenTimeRepository: StrictFakeScreenTimeRepository()
        )
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

    // MARK: - 4. 연장 불가 기간 판정 경계

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
        // nil(미적용) → 비활성.
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
        // 연장 불가 모드 적용 전후(같은 그룹, strictUntil만 다름)의 투영본이 == → 불필요한 churn 없음.
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

    // MARK: - 7. 편집 방어(updateRule/updateWeekdayRules/updateSelection)

    @Test func updateRuleBlockedDuringStrictLockAllowedWhenExpired() {
        let useCase = makeManageUseCase()
        let id = UUID()

        // 활성 기간(미래 만료) → 규칙/한도 변경 시도 무시.
        var active = [SharedStore.ScreenTimeGroup(
            id: id, name: "게임", dailyLimitMinutes: 30, ruleKind: .dailyLimit,
            isApplied: true, strictUntil: .distantFuture
        )]
        useCase.updateRule(id: id, kind: .cooldown, dailyLimitMinutes: 99, in: &active)
        #expect(active[0].ruleKind == .dailyLimit)      // 무변경
        #expect(active[0].dailyLimitMinutes == 30)      // 무변경

        // 비활성(만료 지난 strictUntil) → 정상 변경.
        var expired = [SharedStore.ScreenTimeGroup(
            id: id, name: "게임", dailyLimitMinutes: 30, ruleKind: .dailyLimit,
            isApplied: true, strictUntil: .distantPast
        )]
        useCase.updateRule(id: id, kind: .dailyLimit, dailyLimitMinutes: 99, in: &expired)
        #expect(expired[0].dailyLimitMinutes == 99)     // 변경됨
    }

    @Test func updateWeekdayRulesBlockedDuringStrictLockAllowedWhenExpired() {
        let useCase = makeManageUseCase()
        let valid = indexedRules()

        var active = [SharedStore.ScreenTimeGroup(
            id: UUID(), name: "게임", ruleKind: .dailyLimit, isApplied: true, strictUntil: .distantFuture
        )]
        let idA = active[0].id
        useCase.updateWeekdayRules(id: idA, rules: valid, in: &active)
        #expect(active[0].weekdayRules == nil)          // 무변경(원래 nil 유지)

        var expired = [SharedStore.ScreenTimeGroup(
            id: UUID(), name: "게임", ruleKind: .dailyLimit, isApplied: true, strictUntil: .distantPast
        )]
        let idE = expired[0].id
        useCase.updateWeekdayRules(id: idE, rules: valid, in: &expired)
        #expect(expired[0].weekdayRules == valid)       // 변경됨
    }

    @Test func updateSelectionBlockedDuringStrictLockAllowedWhenExpired() {
        let useCase = makeManageUseCase()

        var active = [SharedStore.ScreenTimeGroup(
            id: UUID(), name: "게임", ruleKind: .dailyLimit, isApplied: true, strictUntil: .distantFuture
        )]
        let idA = active[0].id
        useCase.updateSelection(id: idA, selection: validSelection(), in: &active)
        #expect(active[0].selectionCount == 0)          // 무변경(빈 선택 유지)

        var expired = [SharedStore.ScreenTimeGroup(
            id: UUID(), name: "게임", ruleKind: .dailyLimit, isApplied: true, strictUntil: .distantPast
        )]
        let idE = expired[0].id
        useCase.updateSelection(id: idE, selection: validSelection(), in: &expired)
        #expect(expired[0].selectionCount == 1)         // 변경됨
    }

    @Test func updateNameAllowedDuringStrictLock() {
        // 이름 변경은 집행 무관이라 연장 불가 기간 중에도 허용된다.
        let useCase = makeManageUseCase()
        let id = UUID()
        var groups = [SharedStore.ScreenTimeGroup(
            id: id, name: "게임", ruleKind: .dailyLimit, isApplied: true, strictUntil: .distantFuture
        )]
        useCase.updateName(id: id, name: "새 이름", in: &groups)
        #expect(groups[0].name == "새 이름")
    }

    // MARK: - 8. 삭제 방어(deleteGroup)

    @Test func deleteGroupBlockedDuringStrictLockAllowedWhenExpired() {
        let useCase = makeManageUseCase()

        // 활성 기간 → false + 배열 보존.
        let idA = UUID()
        var active = [SharedStore.ScreenTimeGroup(
            id: idA, name: "게임", ruleKind: .dailyLimit, isApplied: true, strictUntil: .distantFuture
        )]
        #expect(useCase.deleteGroup(id: idA, in: &active) == false)
        #expect(active.contains { $0.id == idA })

        // 비활성 → true + 제거.
        let idE = UUID()
        var expired = [SharedStore.ScreenTimeGroup(
            id: idE, name: "게임", ruleKind: .dailyLimit, isApplied: true, strictUntil: .distantPast
        )]
        #expect(useCase.deleteGroup(id: idE, in: &expired) == true)
        #expect(expired.isEmpty)
    }

    // MARK: - 9. 연장 불가 모드 적용(activateStrictLock)

    /// 자정 경계 만료 기대값을 코드와 동일하게(.current 캘린더) 계산 — 실행 지역 무관.
    private func expectedExpiry(days: Int, from now: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: now))!
    }

    @Test func activateStrictLockStartsCommitment() {
        // (a) 정상 시작 — strictUntil = 자정 경계 만료, strictStartedAt = now.
        let useCase = makeManageUseCase()
        let now = date(2026, 7, 12, 14, 30)
        let id = UUID()
        var groups = [SharedStore.ScreenTimeGroup(
            id: id, name: "게임", selection: validSelection(),
            dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )]
        #expect(useCase.activateStrictLock(id: id, days: 3, now: now, in: &groups) == true)
        let expiry = expectedExpiry(days: 3, from: now)
        #expect(groups[0].strictUntil == expiry)
        #expect(Calendar.current.startOfDay(for: expiry) == expiry)   // 자정 경계
        #expect(groups[0].strictStartedAt == now)
    }

    @Test func activateStrictLockRejectsDraftGroup() {
        // (b) draft(isApplied=false) 거부.
        let useCase = makeManageUseCase()
        let now = date(2026, 7, 12, 14, 30)
        let id = UUID()
        var groups = [SharedStore.ScreenTimeGroup(
            id: id, name: "게임", selection: validSelection(), ruleKind: .dailyLimit, isApplied: false
        )]
        #expect(useCase.activateStrictLock(id: id, days: 3, now: now, in: &groups) == false)
        #expect(groups[0].strictUntil == nil)
    }

    @Test func activateStrictLockRejectsDaysOutsideRange() {
        // (c) 허용 범위(1...30일) 밖은 거부. 상한 30일은 실수 보호 — 못 푸는 모드라 무한정 긴
        // 연장 불가 기간은 사고가 된다. 범위 안이면 프리셋 칩(1/3/7)에 없는 커스텀 값도 허용한다.
        let useCase = makeManageUseCase()
        let now = date(2026, 7, 12, 14, 30)
        let id = UUID()
        let base = [SharedStore.ScreenTimeGroup(
            id: id, name: "게임", selection: validSelection(),
            dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )]
        for bad in [0, -1, 31, 365] {
            var groups = base
            #expect(useCase.activateStrictLock(id: id, days: bad, now: now, in: &groups) == false)
            #expect(groups[0].strictUntil == nil)
        }
        // 직접 입력 값(프리셋 아님)과 상한값은 허용.
        for good in [2, 12, 30] {
            var groups = base
            #expect(useCase.activateStrictLock(id: id, days: good, now: now, in: &groups) == true)
            #expect(groups[0].strictUntil == expectedExpiry(days: good, from: now))
        }
    }

    @Test func activateStrictLockExtendsToLongerKeepingStart() {
        // (d) 활성 기간 중 더 긴 기간 → 연장 성공 + strictStartedAt 최초 값 유지.
        let useCase = makeManageUseCase()
        let now = date(2026, 7, 12, 14, 30)
        let firstStart = date(2026, 7, 10, 9, 0)
        let id = UUID()
        var groups = [SharedStore.ScreenTimeGroup(
            id: id, name: "게임", selection: validSelection(),
            dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true,
            strictUntil: date(2026, 7, 13, 0, 0), strictStartedAt: firstStart
        )]
        #expect(useCase.activateStrictLock(id: id, days: 7, now: now, in: &groups) == true)
        #expect(groups[0].strictUntil == expectedExpiry(days: 7, from: now))
        #expect(groups[0].strictStartedAt == firstStart)   // 최초 시작 유지
    }

    @Test func activateStrictLockRejectsShorterExpiry() {
        // (e) 활성 기간 중 더 짧은 만료가 되는 시도 → 거부(축소 불가).
        let useCase = makeManageUseCase()
        let now = date(2026, 7, 12, 14, 30)
        let firstStart = date(2026, 7, 10, 9, 0)
        let existingUntil = date(2026, 7, 20, 0, 0)   // 활성, 먼 미래
        let id = UUID()
        var groups = [SharedStore.ScreenTimeGroup(
            id: id, name: "게임", selection: validSelection(),
            dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true,
            strictUntil: existingUntil, strictStartedAt: firstStart
        )]
        #expect(useCase.activateStrictLock(id: id, days: 1, now: now, in: &groups) == false)
        #expect(groups[0].strictUntil == existingUntil)     // 기존 유지
        #expect(groups[0].strictStartedAt == firstStart)
    }

    @Test func activateStrictLockRejectsInvalidGroup() {
        // (f) 유효하지 않은 규칙 그룹(선택 비어 있음 → invalidReason != nil) 거부.
        let useCase = makeManageUseCase()
        let now = date(2026, 7, 12, 14, 30)
        let id = UUID()
        var groups = [SharedStore.ScreenTimeGroup(
            id: id, name: "게임", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )]
        #expect(useCase.activateStrictLock(id: id, days: 3, now: now, in: &groups) == false)
        #expect(groups[0].strictUntil == nil)
    }

    @Test func strictLockDefaultDaysStartsOnShortestPresetChipAndCommits() {
        // (g) 시트 초기 상태 계약(2026-07-31 변경): 기본 기간은 **가장 짧은 프리셋(1일)** 이어야 한다 —
        // 프리셋에서 빠지는 순간 시트가 커스텀 칩 선택 + 휠 펼침으로 열려 처음 화면이 긴 기간을 권한다.
        // 커스텀 시드(14일)는 반대로 **프리셋에 없어야** 커스텀 칩 선택 상태가 유지된다.
        let defaultDays = ManageGroupsUseCase.strictLockDefaultDays
        #expect(ManageGroupsUseCase.strictLockDayRange.contains(defaultDays))
        #expect(defaultDays == ManageGroupsUseCase.strictLockDayPresets.min())
        let seedDays = ManageGroupsUseCase.strictLockCustomSeedDays
        #expect(ManageGroupsUseCase.strictLockDayRange.contains(seedDays))
        #expect(!ManageGroupsUseCase.strictLockDayPresets.contains(seedDays))
        // 기본값 그대로 확정도 가능해야 한다(범위 검증 통과).
        let useCase = makeManageUseCase()
        let now = date(2026, 7, 12, 14, 30)
        let id = UUID()
        var groups = [SharedStore.ScreenTimeGroup(
            id: id, name: "게임", selection: validSelection(),
            dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )]
        #expect(useCase.activateStrictLock(id: id, days: defaultDays, now: now, in: &groups) == true)
        #expect(groups[0].strictUntil == expectedExpiry(days: defaultDays, from: now))
    }

    // MARK: - 10. 전역 설정 판정(hasActiveStrictLock)

    @Test func hasActiveStrictLockReflectsAppliedActiveCommitments() {
        // 전역 설정(denyAppRemoval·자동 날짜)의 on/off 판정: 적용 + 활성 연장 불가 그룹이 있을 때만 true.
        let original = SharedStore.screenTimeGroups
        defer { SharedStore.screenTimeGroups = original }

        SharedStore.screenTimeGroups = [
            SharedStore.ScreenTimeGroup(name: "미적용", ruleKind: .dailyLimit, isApplied: true),
            SharedStore.ScreenTimeGroup(name: "만료", ruleKind: .dailyLimit, isApplied: true, strictUntil: .distantPast),
            SharedStore.ScreenTimeGroup(name: "미적용", ruleKind: .dailyLimit, isApplied: false, strictUntil: .distantFuture)
        ]
        #expect(!SharedStore.hasActiveStrictLock())

        SharedStore.screenTimeGroups += [
            SharedStore.ScreenTimeGroup(name: "활성", ruleKind: .dailyLimit, isApplied: true, strictUntil: .distantFuture)
        ]
        #expect(SharedStore.hasActiveStrictLock())
    }

    // MARK: - 9-b. 기능 토글(설정) — 기본 Off, 연장 불가 기간 중엔 끌 수 없음

    @Test func activateStrictLockRejectedWhenFeatureDisabled() {
        // 설정 토글이 꺼져 있으면(프로덕션 기본값) 켜기가 거부된다 — UI가 진입을 막지만 집행부도 방어.
        let repo = StrictFakeGroupRepository()
        repo.isStrictLockEnabled = false
        let useCase = ManageGroupsUseCase(
            groupRepository: repo,
            screenTimeRepository: StrictFakeScreenTimeRepository()
        )
        let id = UUID()
        var groups = [SharedStore.ScreenTimeGroup(
            id: id, name: "게임", selection: validSelection(),
            dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )]

        #expect(useCase.activateStrictLock(id: id, days: 3, now: date(2026, 7, 12), in: &groups) == false)
        #expect(groups[0].strictUntil == nil)
    }

    @Test func featureToggleCannotBeDisabledWhileCommitmentRuns() {
        // 진행 중인 연장 불가 기간이 있으면 기능 토글을 끌 수 없다 — 끄기로 연장 불가 기간을 우회 해제하는 구멍 차단.
        // 연장 불가 기간이 없으면(또는 만료됐으면) 끌 수 있고, 켜기는 언제나 가능하다.
        let repo = StrictFakeGroupRepository()
        let useCase = ManageGroupsUseCase(
            groupRepository: repo,
            screenTimeRepository: StrictFakeScreenTimeRepository()
        )

        repo.screenTimeGroups = [SharedStore.ScreenTimeGroup(
            id: UUID(), name: "게임", selection: validSelection(),
            ruleKind: .dailyLimit, isApplied: true, strictUntil: .distantFuture
        )]
        #expect(useCase.hasActiveStrictLock())
        #expect(useCase.setStrictLockEnabled(false) == false)
        #expect(repo.isStrictLockEnabled)              // 끄기 거부 → 켜진 상태 유지

        // 만료된 연장 불가 기간만 남으면 끌 수 있다.
        repo.screenTimeGroups = [SharedStore.ScreenTimeGroup(
            id: UUID(), name: "게임", selection: validSelection(),
            ruleKind: .dailyLimit, isApplied: true, strictUntil: .distantPast
        )]
        #expect(!useCase.hasActiveStrictLock())
        #expect(useCase.setStrictLockEnabled(false) == true)
        #expect(!repo.isStrictLockEnabled)

        // 켜기는 연장 불가 기간 유무와 무관하게 가능.
        #expect(useCase.setStrictLockEnabled(true) == true)
        #expect(repo.isStrictLockEnabled)
    }

    // MARK: - 10-a. 쿨다운 휴식은 연장 불가 모드 중에도 정상 종료·재충전된다 (집행 규칙 무영향)

    @Test func cooldownRestStillEndsAndRechargesDuringStrictLock() {
        // 연장 불가 모드가 막는 것은 "휴식을 광고/1분으로 건너뛰기"이지 휴식 자체가 아니다.
        // 예산을 다 써 휴식에 들어간 그룹은 연장 불가 기간 중에도 시간이 지나면 정상 종료되고 예산이
        // 재충전된다(사용 시간을 정당하게 돌려받는 쿨다운의 핵심). 재충전 경로
        // (endCooldownAndRecharge / handleCooldownTimerEnded / rechargeExpiredCooldowns)에
        // strict guard를 "일관성"을 이유로 넣지 말 것 — 넣으면 휴식이 영영 안 끝난다.
        SharedStore.clearGroupStateForTesting()
        let original = SharedStore.screenTimeGroups
        defer {
            SharedStore.clearGroupStateForTesting()
            SharedStore.screenTimeGroups = original
        }

        let id = UUID()
        SharedStore.screenTimeGroups = [
            SharedStore.ScreenTimeGroup(
                id: id, name: "쿨다운-연장 불가 모드", selection: validSelection(),
                ruleKind: .cooldown, isApplied: true,
                cooldownUsageMinutes: 5, cooldownDurationMinutes: 30,
                strictUntil: .distantFuture
            )
        ]
        // 예산 소진 → 휴식 진입(잠김).
        _ = SharedStore.raiseUsedTime(to: 5, for: id)
        SharedStore.startCooldown(until: Date().addingTimeInterval(30 * 60), for: id)
        #expect(SharedStore.isInCooldown(id))
        #expect(SharedStore.shieldedGroupIDs.contains(id))

        // 휴식 시간 경과 → 재충전(연장 불가 기간 중이어도 막히지 않는다).
        _ = SharedStore.endCooldownAndRecharge(for: id)

        #expect(!SharedStore.isInCooldown(id))
        #expect(!SharedStore.shieldedGroupIDs.contains(id))       // 잠금 해제
        #expect(SharedStore.usedTimeByGroupID[id] == nil)         // 예산 0부터 새 사이클
        #expect(SharedStore.group(id: id)?.isStrictLockActive() == true)   // 연장 불가 기간은 그대로 유지
    }

    // MARK: - 10-b. 하트비트 유지(자정 만료 해제 경로 보장)

    @Test func heartbeatStaysAliveForStrictLockedTimeWindowOnlyGroup() {
        // 시간대-only 구성은 원래 하트비트가 불필요하지만(window는 repeats:true), 연장 불가 기간이
        // 걸리면 유지해야 한다 — 만료는 lazy 판정이라 extension 콜백이 와야 전역 설정
        // (기기 전체 앱 삭제 금지)이 해제된다. 콜백이 없으면 자정 만료 후에도 최대 하루 남는다.
        let window = TimeWindow(startMinuteOfDay: 9 * 60, endMinuteOfDay: 12 * 60)
        let plain = SharedStore.ScreenTimeGroup(
            name: "시간대", selection: validSelection(), ruleKind: .timeWindows,
            timeWindows: [window], isApplied: true
        )
        var strict = plain
        strict.strictUntil = .distantFuture

        // 대조: 연장 불가 모드 없는 시간대-only는 기존대로 하트비트 불필요.
        #expect(!DailyMonitor.needsHeartbeat(for: [plain], appliedGroups: [plain]))
        // 연장 불가 기간 중이면 하트비트 유지.
        #expect(DailyMonitor.needsHeartbeat(for: [strict], appliedGroups: [strict]))

        // 만료된 연장 불가 기간은 다시 불필요(해제까지 마친 뒤엔 슬롯을 돌려준다).
        var expired = plain
        expired.strictUntil = .distantPast
        #expect(!DailyMonitor.needsHeartbeat(for: [expired], appliedGroups: [expired]))
    }

    // MARK: - 11. ExtendGroupUseCase 앞단 거부

    @Test func extendUseCaseRejectsStrictLockedGroup() {
        // 연장 불가 기간 활성 잠긴 그룹 → extendOneMinute/extendWithAd가 .strictLockActive를 돌려주고
        // repository의 extendGroup은 호출되지 않는다(집행부 진입 차단).
        let id = UUID()
        let shieldRepo = StrictFakeShieldRepository()
        shieldRepo.lockedGroupsValue = [SharedStore.ScreenTimeGroup(
            id: id, name: "게임", ruleKind: .dailyLimit, isApplied: true, strictUntil: .distantFuture
        )]
        let screenTimeRepo = StrictFakeScreenTimeRepository()
        let useCase = ExtendGroupUseCase(
            shieldRepository: shieldRepo,
            screenTimeRepository: screenTimeRepo
        )

        if case .failure(let f) = useCase.extendOneMinute(groupID: id) {
            #expect(f == .strictLockActive)
        } else {
            Issue.record("extendOneMinute이 실패를 돌려주지 않았다")
        }
        if case .failure(let f) = useCase.extendWithAd(groupID: id) {
            #expect(f == .strictLockActive)
        } else {
            Issue.record("extendWithAd가 실패를 돌려주지 않았다")
        }
        #expect(screenTimeRepo.extendCallCount == 0)
    }

    // MARK: - 11. Presentation — ContentViewModel 진입 차단·확정

    /// 강력 잠금(연장 불가 기간 활성) 그룹 + 유효 규칙(앱 선택 포함)의 applied 그룹을 만든다.
    private func strictActiveGroup() -> SharedStore.ScreenTimeGroup {
        SharedStore.ScreenTimeGroup(
            id: UUID(), name: "게임", selection: validSelection(),
            dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true,
            strictUntil: .distantFuture, strictStartedAt: date(2026, 7, 10, 9, 0)
        )
    }

    private func makeContentViewModel(
        groups: [SharedStore.ScreenTimeGroup],
        groupRepository: StrictFakeGroupRepository = StrictFakeGroupRepository(),
        analytics: StrictFakeAnalyticsRepository = StrictFakeAnalyticsRepository()
    ) -> ContentViewModel {
        groupRepository.screenTimeGroups = groups
        let screenTimeRepo = StrictFakeScreenTimeRepository()
        let defaults = UserDefaults(suiteName: "StrictLockTests.\(UUID().uuidString)")!
        defaults.set(true, forKey: "hasCompletedInitialHomeEntry")
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepository,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: SyncProtectionUseCase(
                groupRepository: groupRepository,
                screenTimeRepository: screenTimeRepo
            ),
            loadDashboardUseCase: LoadDashboardUseCase(
                shieldRepository: StrictFakeShieldRepository(),
                statsRepository: StrictFakeStatsRepository(),
                screenTimeRepository: screenTimeRepo
            ),
            authorizeUseCase: AuthorizeUseCase(
                authRepository: StrictFakeAuthorizationRepository(),
                notificationRepository: StrictFakeNotificationRepository()
            ),
            analyticsRepository: analytics,
            userDefaults: defaults
        )
        viewModel.groups = groups
        return viewModel
    }

    @Test func presentRuleEditorBlockedDuringStrictLock() {
        // 연장 불가 기간 중인 그룹의 규칙 편집기 진입은 막히고(ruleEditorGroupID nil 유지) 안내 alert가 뜬다.
        let group = strictActiveGroup()
        let viewModel = makeContentViewModel(groups: [group])

        viewModel.presentRuleEditor(for: group)

        #expect(viewModel.ruleEditorGroupID == nil)
        #expect(viewModel.alertMessage != nil)
    }

    @Test func requestDeleteBlockedDuringStrictLock() {
        // 연장 불가 기간 중인 그룹의 삭제 진입은 막히고 그룹이 보존되며 안내 alert가 뜬다(광고 게이트 미진입).
        let group = strictActiveGroup()
        let viewModel = makeContentViewModel(groups: [group])

        viewModel.requestDeleteGroup(group.id)

        #expect(viewModel.groups.contains { $0.id == group.id })
        #expect(!viewModel.isAdGatePresented)
        #expect(viewModel.alertMessage != nil)
    }

    @Test func deleteGroupPreservesStrictLockedGroup() {
        // deleteGroup 직접 호출(광고 게이트 완료 후 경로)도 Domain 방어로 그룹을 보존한다.
        let group = strictActiveGroup()
        let viewModel = makeContentViewModel(groups: [group])

        viewModel.deleteGroup(group.id)

        #expect(viewModel.groups.contains { $0.id == group.id })
        #expect(viewModel.alertMessage != nil)
    }

    @Test func confirmStrictLockSetsExpiryAndClosesSheet() {
        // 미적용 applied 그룹에 연장 불가 모드 적용 → strictUntil 세팅 + 시트 닫힘 + strict_lock_commit 로깅.
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "게임", selection: validSelection(),
            dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )
        let analytics = StrictFakeAnalyticsRepository()
        let viewModel = makeContentViewModel(groups: [group], analytics: analytics)

        viewModel.presentStrictLockSheet(for: group)
        #expect(viewModel.strictLockSheetGroupID == group.id)

        viewModel.confirmStrictLock(days: 3)

        #expect(viewModel.strictLockSheetGroupID == nil)
        #expect(viewModel.groups.first?.strictUntil != nil)
        #expect(analytics.events.contains { $0.name == "strict_lock_commit" })
        #expect(analytics.userProperties["active_rule_profile"] == "wd0_dl1_tw0_cd0")
        #expect(analytics.userProperties["strict_rule_profile"] == "wd0_dl1_tw0_cd0")
    }

    @Test func presentStrictLockSheetIgnoredForDraftGroup() {
        // draft(미적용) 그룹은 연장 불가 시트를 열 수 없다.
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "게임", selection: validSelection(), ruleKind: .dailyLimit, isApplied: false
        )
        let viewModel = makeContentViewModel(groups: [group])

        viewModel.presentStrictLockSheet(for: group)

        #expect(viewModel.strictLockSheetGroupID == nil)
    }

    @Test func presentStrictLockSheetBlockedForInvalidAppliedGroup() {
        // applied이지만 무효한 그룹(항목 0개 — 적용 후 picker에서 전부 해제)은 시트를 열지 않고
        // 사유를 안내한다. 열어주면 activateStrictLock이 같은 검증으로 거부해 최종 확인을 눌러도
        // 확정이 조용히 실패하고, 사용자는 연장 불가 모드가 켜졌다고 오인한다.
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "게임", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )
        let viewModel = makeContentViewModel(groups: [group])

        viewModel.presentStrictLockSheet(for: group)

        #expect(viewModel.strictLockSheetGroupID == nil)
        #expect(viewModel.alertMessage != nil)
    }

    @Test func presentStrictLockSheetOpensForActiveCommitmentEvenIfInvalid() {
        // 이미 연장 불가 기간 중인 그룹은 편집이 막혀 무효가 될 수 없으므로 유효성 검증을 건너뛰고
        // 현황·연장 진입을 허용한다(방어적 — 진입까지 막으면 만료일도 못 본다).
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "게임", dailyLimitMinutes: 30, ruleKind: .dailyLimit,
            isApplied: true, strictUntil: .distantFuture
        )
        let viewModel = makeContentViewModel(groups: [group])

        viewModel.presentStrictLockSheet(for: group)

        #expect(viewModel.strictLockSheetGroupID == group.id)
        #expect(viewModel.alertMessage == nil)
    }

    // MARK: - 12. Presentation — HomeViewModel 남은 일수·배지

    private func makeHomeViewModel(groups: [SharedStore.ScreenTimeGroup]) -> HomeViewModel {
        HomeViewModel(
            groups: groups,
            todayStats: DailyStats(dateKey: "2026-07-12"),
            isMonitoring: true,
            isShieldActive: false,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil
        )
    }

    @Test func strictRemainingDaysCountsWholeDays() {
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "게임", ruleKind: .dailyLimit, isApplied: true,
            strictUntil: date(2026, 7, 15, 0, 0)   // 3일 연장 불가 기간(7/12~7/14, 7/15 0시 해제)
        )
        let viewModel = makeHomeViewModel(groups: [group])

        // 켠 날(7/12) = 3, 마지막 날(7/14) = 1.
        #expect(viewModel.strictRemainingDays(for: group, now: date(2026, 7, 12, 14, 30), calendar: calendar) == 3)
        #expect(viewModel.strictRemainingDays(for: group, now: date(2026, 7, 14, 10, 0), calendar: calendar) == 1)
        // 만료(7/15 0시) 이후 = nil.
        #expect(viewModel.strictRemainingDays(for: group, now: date(2026, 7, 15, 0, 0), calendar: calendar) == nil)

        // 미적용 그룹 = nil.
        let plain = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", ruleKind: .dailyLimit, isApplied: true)
        #expect(viewModel.strictRemainingDays(for: plain, now: date(2026, 7, 12, 14, 30), calendar: calendar) == nil)
    }

    @Test func strictBadgeTextPresentOnlyWhileActive() {
        let viewModel = makeHomeViewModel(groups: [])
        let active = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "게임", ruleKind: .dailyLimit, isApplied: true, strictUntil: .distantFuture
        )
        let plain = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", ruleKind: .dailyLimit, isApplied: true)

        #expect(viewModel.strictBadgeText(for: active) != nil)
        #expect(viewModel.strictBadgeText(for: plain) == nil)
    }

    // MARK: - 13. Presentation — LockOptionsViewModel 연장 차단

    @Test func lockOptionsBlocksExtensionForStrictLockedGroup() {
        // 연장 불가 기간 잠긴 그룹 선택 시 1분·광고 연장 모두 비활성 + 안내 문구 노출("그만 쓰기"는 유지).
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "게임", selection: validSelection(),
            ruleKind: .dailyLimit, isApplied: true, strictUntil: .distantFuture
        )
        let shieldRepo = StrictFakeShieldRepository()
        shieldRepo.lockedGroupsValue = [group]
        shieldRepo.oneMinuteRemaining = 5   // 연장 차단이 strict 때문임을 분명히 한다.
        let viewModel = LockOptionsViewModel(
            extendGroupUseCase: ExtendGroupUseCase(
                shieldRepository: shieldRepo,
                screenTimeRepository: StrictFakeScreenTimeRepository()
            ),
            analyticsRepository: StrictFakeAnalyticsRepository()
        )

        viewModel.onAppear()

        #expect(viewModel.isSelectedGroupStrictLocked)
        #expect(!viewModel.canExtendOneMinute)
        #expect(!viewModel.canExtendWithAd)
        #expect(viewModel.strictLockNotice != nil)
    }
}

// MARK: - 테스트 스텁(최소 프로토콜 충족)

private final class StrictFakeGroupRepository: GroupRepository {
    var screenTimeGroups: [ScreenTimeGroup] = []
    func defaultGroupName(for index: Int) -> String { "그룹 \(index + 1)" }
    /// 연장 불가 기능 토글. 대부분의 테스트가 연장 불가 기간 켜기를 다루므로 기본 On으로 둔다
    /// (기본 Off인 프로덕션 기본값은 `activateStrictLockRejectedWhenFeatureDisabled`가 검증).
    var isStrictLockEnabled: Bool = true
}

private final class StrictFakeScreenTimeRepository: ScreenTimeRepository {
    var isDailyMonitoringEnabled = false
    private(set) var extendCallCount = 0

    func rolloverCounterIfNeeded() {}
    @discardableResult func reapplyShieldIfOverrideExpired() -> Bool { false }
    func syncDailyMonitoring(groups: [ScreenTimeGroup]) throws {}
    func reconnectMonitoring() throws {}
    func validDailyMonitoringGroups(from groups: [ScreenTimeGroup]) -> [ScreenTimeGroup] { groups }
    func monitoredGroupIDs() -> Set<UUID> { [] }
    func extendGroup(
        groupID: UUID,
        duration seconds: Int,
        source: ExtensionSource
    ) -> Result<GroupExtensionResult, ExtensionFailure> {
        extendCallCount += 1
        return .failure(.groupNotFound)
    }
    func isNearMidnightOverrideCutoff(now: Date) -> Bool { false }
    func isWithinNearMidnightNoticeWindow(now: Date) -> Bool { false }
}

private final class StrictFakeShieldRepository: ShieldRepository {
    var isShieldActive = false
    var currentShieldOverrideUntil: Date?
    var overrideUntilByGroupID: [UUID: Date] = [:]
    var usedTimeByGroupID: [UUID: Int] = [:]
    var overrideBaselineUsedTimeByGroupID: [UUID: Int] = [:]
    var overrideGrantedMinutesByGroupID: [UUID: Int] = [:]
    var cooldownEndByGroupID: [UUID: Date] = [:]
    var oneMinuteRemaining = 5
    var lastRequestedUnlockApplicationToken: ApplicationToken?
    var lastRequestedUnlockWebDomainToken: WebDomainToken?
    var lockedGroupsValue: [ScreenTimeGroup] = []

    func lockedGroups() -> [ScreenTimeGroup] { lockedGroupsValue }
    func lockedGroups(containing token: ApplicationToken) -> [ScreenTimeGroup] { lockedGroupsValue }
    func lockedGroups(containing token: WebDomainToken) -> [ScreenTimeGroup] { lockedGroupsValue }
    func groupsInOverride() -> [ScreenTimeGroup] { [] }
    func hasPendingShieldOpenRequest() -> Bool { false }
    func clearLastRequestedUnlockTokens() {}
    func clearShieldOpenRequest() {}
    func recordWalkAway() {}
}

private final class StrictFakeStatsRepository: StatsRepository {
    var todayStats = DailyStats(dateKey: "2026-07-12")
    func lastSevenDayStats() -> [DailyStats] { Array(repeating: todayStats, count: 7) }
    func previousSevenDayStats() -> [DailyStats] { Array(repeating: todayStats, count: 7) }
    func lastNDayStats(_ n: Int) -> [DailyStats] { [] }
    func statsForCalendarWeek(weekOffset: Int) -> [DailyStats] { Array(repeating: todayStats, count: 7) }
    func statsForCalendarMonth(monthOffset: Int) -> [DailyStats] { [] }
    func calendarWeekRange(weekOffset: Int) -> (start: Date, end: Date)? { nil }
    func calendarMonthRange(monthOffset: Int) -> (start: Date, end: Date)? { nil }
    func allDailyStats() -> [DailyStats] { [] }
    var oldestStatDate: Date? { nil }
    var trackingStartDate: Date? { nil }
}

private final class StrictFakeAuthorizationRepository: AuthorizationRepository {
    var isAuthorized = true
    func refresh() {}
    func request() async throws {}
    func observeAuthorizationChanges(_ handler: @escaping AuthorizationChangeHandler) -> AuthorizationObservation {
        AuthorizationObservation(onCancel: {})
    }
}

private final class StrictFakeNotificationRepository: NotificationRepository {
    func authorizationState() async -> NotificationPermissionState { .authorized }
    func requestAuthorizationIfNeeded() async -> NotificationPermissionState { .authorized }
    func isNotificationDeferredByScheduledSummary() async -> Bool { false }
    func scheduleWeeklyStatsNotification(weekStartDay: Int) {}
    func scheduleDailyMorningNotification(extraMinutes: Int) {}
    var isDailyMorningNotificationEnabled = true
    func setDailyMorningNotificationEnabled(_ enabled: Bool) {}
    var isUsageAlertEnabled = true
    func setUsageAlertEnabled(_ enabled: Bool) {}
    func clearDeliveredNotifications() {}
}

private final class StrictFakeAnalyticsRepository: AnalyticsRepository {
    private(set) var events: [AnalyticsEvent] = []
    private(set) var userProperties: [String: String?] = [:]
    func log(_ event: AnalyticsEvent) { events.append(event) }
    func setUserProperty(_ value: String?, for name: String) { userProperties[name] = value }
    func recordError(_ error: Error, context: String) {}
}
