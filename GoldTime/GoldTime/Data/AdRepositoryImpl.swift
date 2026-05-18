
import Foundation
import UIKit

final class AdRepositoryImpl: AdRepository {
    private let service: RewardedAdService

    init(service: RewardedAdService = .shared) {
        self.service = service
    }

    var loadState: AdLoadState {
        switch service.loadState {
        case .idle: return .idle
        case .loading: return .loading
        case .ready: return .ready
        case .failed: return .failed
        }
    }

    func loadAd() { service.loadAd() }

    func present(
        from viewController: UIViewController,
        onDismissed: @escaping (Bool) -> Void
    ) {
        service.present(from: viewController, onDismissed: onDismissed)
    }
}
