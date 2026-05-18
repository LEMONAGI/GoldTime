
import Foundation
import UIKit

enum AdLoadState: Equatable {
    case idle
    case loading
    case ready
    case failed
}

protocol AdRepository {
    var loadState: AdLoadState { get }
    func loadAd()
    func present(
        from viewController: UIViewController,
        onDismissed: @escaping (_ didEarnReward: Bool) -> Void
    )
}
