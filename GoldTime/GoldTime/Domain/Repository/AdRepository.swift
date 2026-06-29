
import Foundation
import UIKit

enum AdLoadState: Equatable {
    case idle
    case loading
    case ready
    case failed
}

enum RewardedAdPlacement: Equatable {
    case shieldUnlock
    case groupEditGate

    /// GA4 파라미터(`placement`)용 안정적 snake_case 식별자. 대시보드가 이 값으로 두 용처를
    /// 구분한다(잠금 해제 vs 편집 게이트). 값 변경은 대시보드 쿼리와 함께 바꿔야 한다.
    var analyticsValue: String {
        switch self {
        case .shieldUnlock: return "shield_unlock"
        case .groupEditGate: return "group_edit_gate"
        }
    }
}

protocol AdRepository {
    func loadState(for placement: RewardedAdPlacement) -> AdLoadState
    func loadAd(for placement: RewardedAdPlacement)
    func present(
        from viewController: UIViewController,
        placement: RewardedAdPlacement,
        onDismissed: @escaping (_ didEarnReward: Bool) -> Void
    )
}
