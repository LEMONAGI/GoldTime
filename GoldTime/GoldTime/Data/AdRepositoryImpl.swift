
import Foundation
import UIKit

final class AdRepositoryImpl: AdRepository {
    private let service: RewardedAdService

    init(service: RewardedAdService = .shared) {
        self.service = service
    }

    func loadState(for placement: RewardedAdPlacement) -> AdLoadState {
        switch service.loadState(for: placement.servicePlacement) {
        case .idle: return .idle
        case .loading: return .loading
        case .ready: return .ready
        case .failed: return .failed
        }
    }

    func loadAd(for placement: RewardedAdPlacement) {
        service.loadAd(for: placement.servicePlacement)
    }

    func present(
        from viewController: UIViewController,
        placement: RewardedAdPlacement,
        onDismissed: @escaping (Bool) -> Void
    ) {
        service.present(
            from: viewController,
            placement: placement.servicePlacement,
            onDismissed: onDismissed
        )
    }
}

private extension RewardedAdPlacement {
    var servicePlacement: RewardedAdService.Placement {
        switch self {
        case .shieldUnlock: return .shieldUnlock
        case .groupEditGate: return .groupEditGate
        }
    }
}
