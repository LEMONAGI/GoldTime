
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

    private let adRepository: any AdRepository
    private let onComplete: () -> Void
    private let onCancel: () -> Void

    init(
        adRepository: (any AdRepository)? = nil,
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.adRepository = adRepository ?? AdRepositoryImpl()
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var loadState: AdLoadState {
        adRepository.loadState
    }

    func onAppear() {
        switch adRepository.loadState {
        case .ready:
            break
        case .failed:
            showFallback = true
        default:
            adRepository.loadAd()
        }
    }

    func handleLoadStateChange(_ state: AdLoadState, viewController: UIViewController?) {
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
        guard let viewController, case .ready = adRepository.loadState, !isPresenting else { return }
        isPresenting = true
        adRepository.present(from: viewController) { [weak self] earned in
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
