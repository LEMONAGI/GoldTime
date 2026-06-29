
//
//  RewardedAdViewModel.swift
//  GoldTime
//

import Foundation
import UIKit

@MainActor
@Observable
final class RewardedAdViewModel {
    var isPresenting = false
    var showFallback = false

    private let placement: RewardedAdPlacement
    private let adRepository: any AdRepository
    private let analyticsRepository: any AnalyticsRepository
    private let onComplete: () -> Void
    private let onCancel: () -> Void

    init(
        placement: RewardedAdPlacement = .shieldUnlock,
        adRepository: (any AdRepository)? = nil,
        analyticsRepository: (any AnalyticsRepository)? = nil,
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.placement = placement
        self.adRepository = adRepository ?? AdRepositoryImpl()
        self.analyticsRepository = analyticsRepository ?? AnalyticsRepositoryImpl()
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var loadState: AdLoadState {
        adRepository.loadState(for: placement)
    }

    func onAppear() {
        switch adRepository.loadState(for: placement) {
        case .ready:
            break
        case .failed:
            presentFallback()
        default:
            adRepository.loadAd(for: placement)
        }
    }

    func handleLoadStateChange(_ state: AdLoadState, viewController: UIViewController?) {
        switch state {
        case .ready:
            presentIfReady(from: viewController)
        case .failed:
            presentFallback()
        default:
            break
        }
    }

    func presentIfReady(from viewController: UIViewController?) {
        guard let viewController,
              case .ready = adRepository.loadState(for: placement),
              !isPresenting
        else {
            return
        }
        isPresenting = true
        analyticsRepository.log(.adStarted(placement: placement.analyticsValue))
        adRepository.present(from: viewController, placement: placement) { [weak self] earned in
            guard let self else { return }
            Task { @MainActor in
                if earned {
                    self.analyticsRepository.log(.adRewardEarned(placement: self.placement.analyticsValue))
                    self.onComplete()
                } else {
                    self.analyticsRepository.log(.adClosedNoReward(placement: self.placement.analyticsValue))
                    self.onCancel()
                }
            }
        }
    }

    func cancel() {
        onCancel()
    }

    func completeFallback() {
        analyticsRepository.log(.adFallbackUsed(placement: placement.analyticsValue))
        onComplete()
    }

    /// 광고를 띄우지 못해 fallback(무료 연장) UI로 전환한다. 로드 실패 경로가 둘(onAppear,
    /// handleLoadStateChange)이라 이미 전환된 경우 `ad_unavailable` 중복 로깅을 막는다.
    private func presentFallback() {
        guard !showFallback else { return }
        showFallback = true
        analyticsRepository.log(.adUnavailable(placement: placement.analyticsValue))
    }
}
