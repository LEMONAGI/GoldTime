
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
