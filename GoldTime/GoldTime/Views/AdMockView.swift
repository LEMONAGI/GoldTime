//
//  AdMockView.swift
//  GoldTime
//

import GoogleMobileAds
import SwiftUI

struct AdMockView: View {
    let onComplete: () -> Void
    let onCancel: () -> Void

    private var adService: RewardedAdService { RewardedAdService.shared }
    @State private var viewController: UIViewController?
    @State private var isPresenting = false
    @State private var showFallback = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if showFallback { fallbackView } else { loadingView }
            ViewControllerBridge { vc in
                viewController = vc
                presentIfReady()
            }
            .frame(width: 0, height: 0)
        }
        .onAppear {
            switch adService.loadState {
            case .ready: break
            case .failed: showFallback = true
            default: adService.loadAd()
            }
        }
        .onChange(of: adService.loadState) { _, state in
            switch state {
            case .ready: presentIfReady()
            case .failed: showFallback = true
            default: break
            }
        }
    }

    private func presentIfReady() {
        guard let vc = viewController, case .ready = adService.loadState, !isPresenting else { return }
        isPresenting = true
        adService.present(from: vc) { earned in
            earned ? onComplete() : onCancel()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("📺").font(.system(size: 64))
            Text("광고 준비 중").font(.title2.bold()).foregroundStyle(.white)
            ProgressView().tint(Color.goldPrimary)
            Spacer()
            Button("취소", role: .cancel) { onCancel() }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 32)
        }
    }

    private var fallbackView: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("광고를 불러올 수 없어요").font(.title2.bold()).foregroundStyle(.white)
            Text("네트워크 상태를 확인해 주세요").foregroundStyle(.white.opacity(0.7))
            Spacer()
            VStack(spacing: 12) {
                Button("그래도 15분 사용하기") { onComplete() }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.goldPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button("취소", role: .cancel) { onCancel() }
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
