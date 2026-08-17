
import Foundation

/// 추적할 핵심 사용자 행동. 이벤트 이름/파라미터를 한곳에 모아 오타·난립을 막는다.
///
/// - Firebase 이벤트 이름 규칙: 영문 소문자+`_`, 40자 이내, `firebase_`/`google_`/`ga_` 접두사 금지.
/// - 파라미터 키는 40자 이내, 값은 100자 이내(문자열) 권장.
/// - `custom`은 extension 대기 큐(`SharedStore.PendingAnalyticsEvent`)를 드레인할 때 사용한다.
enum AnalyticsEvent {
    /// 앱 활성화 시 현재 적용 그룹 수를 한 번 기록한다. 0개 사용자도 포함한다.
    /// 최대 5개라 버킷 없이 정수 그대로 보낸다(GA4 custom metric — 평균 그룹 수를 바로 본다).
    case groupSnapshot(appliedGroupCount: Int, snapshotID: String)
    case groupApplied(payload: RuleGroupSnapshotAnalytics)
    case groupDeleted(wasApplied: Bool)
    case shieldExtendOptionsViewed(
        entrySource: String,
        lockedGroupCount: Int,
        strictLockedGroupCount: Int,
        oneMinuteRemaining: Int,
        nearMidnight: Bool
    )
    case shieldExtendStopSelected(lockedGroupCount: Int)
    case shieldExtendMethodSelected(method: String)
    case shieldExtendCompleted(method: String, seconds: Int, payload: ShieldExtendAnalyticsPayload)
    case shieldExtendFailed(method: String, reason: String)
    /// 앱 활성화 시 적용 그룹 하나의 현재 규칙 구성을 기록한다.
    case ruleGroupSnapshot(payload: RuleGroupSnapshotAnalytics, snapshotID: String)
    /// 연장 불가 모드 최초 시작. days = 이번에 선택한 기간.
    case strictLockStarted(days: Int, payload: RuleGroupSnapshotAnalytics)
    /// 이미 활성인 연장 불가 기간의 연장. days = 이번에 선택한 기간.
    case strictLockExtended(days: Int, payload: RuleGroupSnapshotAnalytics)
    /// 권한 철회 없이 설정된 만료 시각까지 도달한 연장 불가 기간.
    /// days는 시작·연장의 "이번 선택분"과 달리 최초 시작~최종 만료의 **총 기간**이라
    /// 파라미터 이름을 `strict_lock_total_days`로 분리한다(같은 이름이면 GA4에서 섞여 평균이 무의미해진다).
    case strictLockCompleted(totalDays: Int)
    /// 스크린타임 권한 철회로 연장 불가 기간이 풀린 상태를 복구 화면에서 감지. (권한 재승인 유도용 관측)
    case strictLockRevokeDetected

    // MARK: - 대시보드 퍼널 (Reward 광고 / Activation)
    // placement는 Core의 `RewardedAdService.Placement`를 안정적 snake_case 문자열로 매핑한 값
    // (예: "shield_unlock", "group_edit_gate"). Domain은 Core에 의존하지 않으므로 String으로 받는다.
    case adStarted(placement: String)
    case adRewardEarned(placement: String)
    case adClosedNoReward(placement: String)
    case adUnavailable(placement: String)
    case adFallbackUsed(placement: String)
    case onboardingEntered
    case onboardingCompleted

    case custom(name: String, parameters: [String: Any])

    var name: String {
        switch self {
        case .groupSnapshot: return "group_snapshot"
        case .groupApplied: return "group_applied"
        case .groupDeleted: return "group_deleted"
        case .shieldExtendOptionsViewed: return "shield_extend_options_viewed"
        case .shieldExtendStopSelected: return "shield_extend_stop_selected"
        case .shieldExtendMethodSelected: return "shield_extend_method_selected"
        case .shieldExtendCompleted: return "shield_extend_completed"
        case .shieldExtendFailed: return "shield_extend_failed"
        case .ruleGroupSnapshot(let payload, _): return payload.eventName
        case .strictLockStarted: return "strict_lock_started"
        case .strictLockExtended: return "strict_lock_extended"
        case .strictLockCompleted: return "strict_lock_completed"
        case .strictLockRevokeDetected: return "strict_lock_revoke_detected"
        case .adStarted: return "ad_started"
        case .adRewardEarned: return "ad_reward_earned"
        case .adClosedNoReward: return "ad_closed_no_reward"
        case .adUnavailable: return "ad_unavailable"
        case .adFallbackUsed: return "ad_fallback_used"
        case .onboardingEntered: return "onboarding_entered"
        case .onboardingCompleted: return "onboarding_completed"
        case .custom(let name, _): return name
        }
    }

    var parameters: [String: Any] {
        switch self {
        case .groupSnapshot(let count, let snapshotID):
            return [
                "applied_group_count": Self.appliedGroupCountValue(count),
                "snapshot_id": snapshotID
            ]
        case .groupApplied(let payload):
            return [
                "rule_mode": payload.ruleMode,
                "selection_count_bucket": payload.selectionCountBucket
            ]
        case .groupDeleted(let wasApplied):
            return ["was_applied": String(wasApplied)]
        case .shieldExtendOptionsViewed(
            let entrySource,
            let lockedGroupCount,
            let strictLockedGroupCount,
            let oneMinuteRemaining,
            let nearMidnight
        ):
            return [
                "entry_source": entrySource,
                "locked_group_count": lockedGroupCount,
                "strict_locked_group_count": strictLockedGroupCount,
                "one_minute_remaining": oneMinuteRemaining,
                "near_midnight": String(nearMidnight)
            ]
        case .shieldExtendStopSelected(let lockedGroupCount):
            return ["locked_group_count": lockedGroupCount]
        case .shieldExtendMethodSelected(let method):
            return ["extend_method": method]
        case .shieldExtendCompleted(let method, let seconds, let payload):
            var parameters = payload.parameters
            parameters["extend_method"] = method
            parameters["extend_seconds"] = seconds
            return parameters
        case .shieldExtendFailed(let method, let reason):
            return [
                "extend_method": method,
                "failure_reason": reason
            ]
        case .ruleGroupSnapshot(let payload, let snapshotID):
            var parameters = payload.parameters
            parameters["snapshot_id"] = snapshotID
            return parameters
        case .strictLockStarted(let days, let payload),
             .strictLockExtended(let days, let payload):
            var parameters = payload.parameters
            parameters["strict_lock_days"] = days
            return parameters
        case .strictLockCompleted(let totalDays):
            return ["strict_lock_total_days": totalDays]
        case .strictLockRevokeDetected: return [:]
        case .adStarted(let placement),
             .adRewardEarned(let placement),
             .adClosedNoReward(let placement),
             .adUnavailable(let placement),
             .adFallbackUsed(let placement):
            return ["placement": placement]
        case .onboardingEntered, .onboardingCompleted: return [:]
        case .custom(_, let parameters): return parameters
        }
    }

    /// 손상·미래 데이터가 분포를 왜곡하지 않도록 정책 상한(0...maxGroupCount)으로 clamp한다.
    private static func appliedGroupCountValue(_ count: Int) -> Int {
        min(max(count, 0), ScreenTimeGroupPolicy.maxGroupCount)
    }
}

protocol AnalyticsRepository {
    func log(_ event: AnalyticsEvent)
    func setUserProperty(_ value: String?, for name: String)
    func recordError(_ error: Error, context: String)
    func recordStrictLockCommitment(groupID: UUID, startedAt: Date, expiresAt: Date)
    /// 철회로 무효가 된 약정만 지운다. **"전부 지우기"는 두지 않는다** — 미승인으로 읽힌 순간
    /// 일괄 폐기하던 구현이 콜드 스타트의 transient `false` 한 번에 완주 데이터를 날렸다(2026-08-17).
    /// 폐기는 복구 화면 도달처럼 철회 증거가 있는 경로에서 그룹을 특정해서만 한다.
    func discardStrictLockCommitments(groupIDs: [UUID])
    func drainCompletedStrictLockDays(at now: Date) -> [Int]
}
