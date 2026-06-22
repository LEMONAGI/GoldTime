
import Foundation

/// 추적할 핵심 사용자 행동. 이벤트 이름/파라미터를 한곳에 모아 오타·난립을 막는다.
///
/// - Firebase 이벤트 이름 규칙: 영문 소문자+`_`, 40자 이내, `firebase_`/`google_`/`ga_` 접두사 금지.
/// - 파라미터 키는 40자 이내, 값은 100자 이내(문자열) 권장.
/// - `custom`은 extension 대기 큐(`SharedStore.PendingAnalyticsEvent`)를 드레인할 때 사용한다.
enum AnalyticsEvent {
    case groupCreated(groupCount: Int)
    case groupApplied(payload: RuleAnalyticsPayload)
    case ruleMonitoringRegistered(payload: RuleAnalyticsPayload)
    case monitoringSynced(appliedGroupCount: Int)
    case authorizationResult(granted: Bool)
    case adUnlock(seconds: Int, payload: RuleAnalyticsPayload)
    case oneMinuteUnlock
    case walkAway(lockedCount: Int)
    case ruleChanged(from: String, to: String, wasLocked: Bool, usedBucket: String, causedLock: Bool)
    case custom(name: String, parameters: [String: Any])

    var name: String {
        switch self {
        case .groupCreated: return "group_created"
        case .groupApplied: return "group_applied"
        case .ruleMonitoringRegistered: return "rule_monitoring_registered"
        case .monitoringSynced: return "monitoring_synced"
        case .authorizationResult: return "authorization_result"
        case .adUnlock: return "ad_unlock"
        case .oneMinuteUnlock: return "one_minute_unlock"
        case .walkAway: return "walk_away"
        case .ruleChanged: return "rule_changed"
        case .custom(let name, _): return name
        }
    }

    var parameters: [String: Any] {
        switch self {
        case .groupCreated(let count): return ["group_count": count]
        case .groupApplied(let payload): return payload.parameters
        case .ruleMonitoringRegistered(let payload): return payload.parameters
        case .monitoringSynced(let count): return ["applied_group_count": count]
        case .authorizationResult(let granted): return ["granted": granted]
        case .adUnlock(let seconds, let payload):
            var parameters = payload.parameters
            parameters["seconds"] = seconds
            return parameters
        case .oneMinuteUnlock: return [:]
        case .walkAway(let count): return ["locked_count": count]
        case .ruleChanged(let from, let to, let wasLocked, let usedBucket, let causedLock):
            return [
                "from_rule": from,
                "to_rule": to,
                "was_locked": wasLocked,
                "used_bucket": usedBucket,
                "caused_lock": causedLock
            ]
        case .custom(_, let parameters): return parameters
        }
    }
}

protocol AnalyticsRepository {
    func log(_ event: AnalyticsEvent)
    func setUserProperty(_ value: String?, for name: String)
    func recordError(_ error: Error, context: String)
}
