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

    private let adProvider: any RewardedAdProviding
    private let onComplete: () -> Void
    private let onCancel: () -> Void

    init(
        adProvider: (any RewardedAdProviding)? = nil,
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.adProvider = adProvider ?? RewardedAdService.shared
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var loadState: RewardedAdService.LoadState {
        adProvider.loadState
    }

    func onAppear() {
        switch adProvider.loadState {
        case .ready:
            break
        case .failed:
            showFallback = true
        default:
            adProvider.loadAd()
        }
    }

    func handleLoadStateChange(_ state: RewardedAdService.LoadState, viewController: UIViewController?) {
        switch state {
        case .ready:
            presentIfReady(from: viewController)
        case .failed:
            showFallback = true
        default:
            break
        }
    }

    func presentIfReady(from viewController: UIViewController?) {
        guard let viewController, case .ready = adProvider.loadState, !isPresenting else { return }
        isPresenting = true
        adProvider.present(from: viewController) { [weak self] earned in
            guard let self else { return }
            Task { @MainActor in
                earned ? self.onComplete() : self.onCancel()
            }
        }
    }

    func cancel() {
        onCancel()
    }

    func completeFallback() {
        onComplete()
    }
}
