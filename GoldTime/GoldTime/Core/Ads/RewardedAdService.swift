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
    enum Placement: Hashable {
        case shieldUnlock
        case groupEditGate
    }

    private var loadStates: [Placement: LoadState] = [
        .shieldUnlock: .idle,
        .groupEditGate: .idle
    ]
    private var rewardedAds: [Placement: RewardedAd] = [:]

    private var dismissCallback: ((_ didEarnReward: Bool) -> Void)?
    private var didEarnReward = false
    private var presentingPlacement: Placement?

    private override init() { super.init() }

    func loadState(for placement: Placement) -> LoadState {
        loadStates[placement] ?? .idle
    }

    func loadAd(for placement: Placement) {
        guard case .idle = loadState(for: placement) else { return }
        loadStates[placement] = .loading
        RewardedAd.load(with: adUnitID(for: placement), request: Request()) { [weak self] ad, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error = error {
                    print("[AdMob] 광고 로드 실패: \(error.localizedDescription)")
                    self.loadStates[placement] = .failed
                    self.rewardedAds[placement] = nil
                } else {
                    self.rewardedAds[placement] = ad
                    self.rewardedAds[placement]?.fullScreenContentDelegate = self
                    self.loadStates[placement] = .ready
                }
            }
        }
    }

    func present(
        from viewController: UIViewController,
        placement: Placement,
        onDismissed: @escaping (_ didEarnReward: Bool) -> Void
    ) {
        guard let ad = rewardedAds[placement], case .ready = loadState(for: placement) else {
            loadStates[placement] = .idle
            DispatchQueue.main.async {
                onDismissed(false)
            }
            return
        }
        dismissCallback = onDismissed
        didEarnReward = false
        presentingPlacement = placement
        ad.present(from: viewController) { [weak self] in
            self?.didEarnReward = true
        }
    }

    private func adUnitID(for placement: Placement) -> String {
        #if DEBUG
        // Debug 빌드는 테스트 기기 등록과 무관하게 항상 Google 공식 테스트 보상형 광고를 띄운다.
        // 실제 광고 단위로 테스트 클릭하면 정책 위반(무효 트래픽)이 되므로 Debug에서는 절대 실 단위를 쓰지 않는다.
        return "ca-app-pub-3940256099942544/1712485313"
        #else
        switch placement {
        case .shieldUnlock:
            return "ca-app-pub-7955752005034474/4426609987"
        case .groupEditGate:
            return "ca-app-pub-7955752005034474/7898408564"
        }
        #endif
    }
}

extension RewardedAdService: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        DispatchQueue.main.async {
            let placement = self.presentingPlacement
            let earned = self.didEarnReward
            if let placement {
                self.rewardedAds[placement] = nil
                self.loadStates[placement] = .idle
            }
            self.dismissCallback?(earned)
            self.dismissCallback = nil
            self.presentingPlacement = nil
            if let placement {
                self.loadAd(for: placement)
            }
        }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        DispatchQueue.main.async {
            if let placement = self.presentingPlacement {
                self.rewardedAds[placement] = nil
                self.loadStates[placement] = .failed
            }
            self.dismissCallback?(false)
            self.dismissCallback = nil
            self.presentingPlacement = nil
        }
    }
}
