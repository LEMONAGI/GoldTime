//
//  RewardedAdService.swift
//  GoldTime
//

import Foundation
import GoogleMobileAds

@Observable
final class RewardedAdService: NSObject {
    static let shared = RewardedAdService()

    enum LoadState: Equatable { case idle, loading, ready, failed }
    private(set) var loadState: LoadState = .idle

    private var rewardedAd: RewardedAd?
    // 실제 광고 단위. Debug 빌드에서는 ConsentService에 등록된 테스트 기기에서만 테스트 광고가 노출된다.
    private let adUnitID = "ca-app-pub-7955752005034474/4426609987"

    private var dismissCallback: ((_ didEarnReward: Bool) -> Void)?
    private var didEarnReward = false

    private override init() { super.init() }

    func loadAd() {
        guard case .idle = loadState else { return }
        loadState = .loading
        RewardedAd.load(with: adUnitID, request: Request()) { [weak self] ad, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error = error {
                    print("[AdMob] 광고 로드 실패: \(error.localizedDescription)")
                    self.loadState = .failed
                    self.rewardedAd = nil
                } else {
                    self.rewardedAd = ad
                    self.rewardedAd?.fullScreenContentDelegate = self
                    self.loadState = .ready
                }
            }
        }
    }

    func present(from viewController: UIViewController, onDismissed: @escaping (_ didEarnReward: Bool) -> Void) {
        guard let ad = rewardedAd, case .ready = loadState else {
            loadState = .idle
            DispatchQueue.main.async {
                onDismissed(false)
            }
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
        DispatchQueue.main.async {
            let earned = self.didEarnReward
            self.rewardedAd = nil
            self.loadState = .idle
            self.dismissCallback?(earned)
            self.dismissCallback = nil
            self.loadAd()
        }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        DispatchQueue.main.async {
            self.rewardedAd = nil
            self.loadState = .failed
            self.dismissCallback?(false)
            self.dismissCallback = nil
        }
    }
}
