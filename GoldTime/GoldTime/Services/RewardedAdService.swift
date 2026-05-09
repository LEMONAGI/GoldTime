//
//  RewardedAdService.swift
//  GoldTime
//

import Foundation
import GoogleMobileAds

@Observable
final class RewardedAdService: NSObject {
    static let shared = RewardedAdService()

    enum LoadState { case idle, loading, ready, failed }
    private(set) var loadState: LoadState = .idle

    private var rewardedAd: RewardedAd?
    // 출시 전 실제 Ad Unit ID로 교체
    private let adUnitID = "ca-app-pub-3940256099942544/1712485313"

    private var dismissCallback: ((_ didEarnReward: Bool) -> Void)?
    private var didEarnReward = false

    private override init() { super.init() }

    static func configure() {
        MobileAds.shared.start(completionHandler: nil)
    }

    func loadAd() {
        guard case .idle = loadState else { return }
        loadState = .loading
        RewardedAd.load(with: adUnitID, request: Request()) { [weak self] ad, error in
            guard let self else { return }
            if error != nil {
                self.loadState = .failed
                self.rewardedAd = nil
            } else {
                self.rewardedAd = ad
                self.rewardedAd?.fullScreenContentDelegate = self
                self.loadState = .ready
            }
        }
    }

    func present(from viewController: UIViewController, onDismissed: @escaping (_ didEarnReward: Bool) -> Void) {
        guard let ad = rewardedAd, case .ready = loadState else {
            loadState = .idle
            onDismissed(false)
            return
        }
        dismissCallback = onDismissed
        didEarnReward = false
        ad.present(from: viewController) { [weak self] in
            self?.didEarnReward = true
        }
    }
}

extension RewardedAdService: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        let earned = didEarnReward
        rewardedAd = nil
        loadState = .idle
        dismissCallback?(earned)
        dismissCallback = nil
        loadAd()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        rewardedAd = nil
        loadState = .failed
        dismissCallback?(false)
        dismissCallback = nil
    }
}
