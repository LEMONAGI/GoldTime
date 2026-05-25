//
//  ConsentFlowModifier.swift
//  GoldTime
//

import SwiftUI
import UIKit

private struct ConsentFlowModifier: ViewModifier {
    @State private var rootVC: UIViewController?

    func body(content: Content) -> some View {
        content
            .background(
                ConsentTriggerView { vc in rootVC = vc }
            )
            .task(id: rootVC != nil) {
                guard let vc = rootVC, !ConsentService.shared.isAdSdkReady else { return }
                await ConsentService.shared.requestConsentAndInitialize(from: vc)
                RewardedAdService.shared.loadAd()
            }
    }
}

private struct ConsentTriggerView: UIViewControllerRepresentable {
    let onAvailable: (UIViewController) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        DispatchQueue.main.async { onAvailable(vc) }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

extension View {
    func withConsentFlow() -> some View {
        modifier(ConsentFlowModifier())
    }
}
