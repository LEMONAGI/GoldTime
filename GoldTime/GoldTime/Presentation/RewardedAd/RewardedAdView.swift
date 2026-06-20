//
//  RewardedAdView.swift
//  GoldTime
//

import GoogleMobileAds
import SwiftUI

struct RewardedAdView: View {
    @State private var viewModel: RewardedAdViewModel

    @State private var viewController: UIViewController?

    private let fallbackLabel: String

    init(
        placement: RewardedAdPlacement = .shieldUnlock,
        fallbackLabel: String = String(localized: "ad.fallbackDefault"),
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.fallbackLabel = fallbackLabel
        _viewModel = State(initialValue: RewardedAdViewModel(
            placement: placement,
            onComplete: onComplete,
            onCancel: onCancel
        ))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if viewModel.showFallback { fallbackView } else { loadingView }
            ViewControllerBridge { vc in
                viewController = vc
                viewModel.presentIfReady(from: vc)
            }
            .frame(width: 0, height: 0)
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onChange(of: viewModel.loadState) { _, state in
            viewModel.handleLoadStateChange(state, viewController: viewController)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(verbatim: "📺").font(.system(size: 64))
            Text("ad.loading").font(.title2.bold()).foregroundStyle(.white)
            ProgressView().tint(Color.accent)
            Spacer()
            Button("common.cancel", role: .cancel) { viewModel.cancel() }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 32)
        }
    }

    private var fallbackView: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("ad.failed.title").font(.title2.bold()).foregroundStyle(.white)
            Text("ad.failed.subtitle").foregroundStyle(.white.opacity(0.7))
            Spacer()
            VStack(spacing: 12) {
                Button(fallbackLabel) { viewModel.completeFallback() }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(GoldTimeButtonStyle(background: Color.accent, foreground: .black, cornerRadius: 12))
                Button("common.cancel", role: .cancel) { viewModel.cancel() }
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 40).padding(.bottom, 32)
        }
    }
}

private struct ViewControllerBridge: UIViewControllerRepresentable {
    let onAvailable: (UIViewController) -> Void
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        DispatchQueue.main.async { onAvailable(vc) }
        return vc
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
