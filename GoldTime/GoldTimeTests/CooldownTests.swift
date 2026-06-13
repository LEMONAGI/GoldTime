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
        // 0분 → usageOutOfRange
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 0, cooldownMinutes: 300) == .usageOutOfRange)
        // 481분 → usageOutOfRange
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 481, cooldownMinutes: 300) == .usageOutOfRange)
        // 경계: 1분, 480분 → nil
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 1, cooldownMinutes: 300) == nil)
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 480, cooldownMinutes: 300) == nil)
    }

    @Test func cooldownPolicyRejectsOutOfRangeCooldown() {
        // 29분 → cooldownOutOfRange
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 10, cooldownMinutes: 29) == .cooldownOutOfRange)
        // 1441분 → cooldownOutOfRange
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 10, cooldownMinutes: 1441) == .cooldownOutOfRange)
        // 경계: 30분, 1440분 → nil
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 10, cooldownMinutes: 30) == nil)
        #expect(CooldownPolicy.firstInvalidReason(usageMinutes: 10, cooldownMinutes: 1440) == nil)
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
}
