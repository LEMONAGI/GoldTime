//
//  ConsentService.swift
//  GoldTime
//

import AppTrackingTransparency
import GoogleMobileAds
import UIKit
import UserMessagingPlatform

@MainActor
final class ConsentService {
    static let shared = ConsentService()
    private(set) var isAdSdkReady = false
    private var consentFlowTask: Task<Void, Never>?
    private var adInitializationTask: Task<Void, Never>?

    private init() {}

    /// UMP 동의 → ATT 순서를 보장한 뒤 AdMob 초기화를 예약한다.
    /// 호출자는 ATT 응답까지만 기다리며, SDK 초기화와 광고 프리로드는 서비스가 계속 소유한다.
    func requestConsentAndBeginAdInitialization() async {
        if let consentFlowTask {
            await consentFlowTask.value
            return
        }

        let task = Task { @MainActor [self] in
            await requestUMPConsent(from: findPresentingViewController())
            await requestATTIfNeeded()
            beginAdInitializationIfNeeded()
        }
        consentFlowTask = task
        await task.value
    }

    // MARK: - Private

    private func findPresentingViewController() -> UIViewController {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.keyWindow?.rootViewController ?? UIViewController()
    }

    private func requestUMPConsent(from viewController: UIViewController) async {
        let params = RequestParameters()
        await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: params) { _ in
                continuation.resume()
            }
        }
        guard ConsentInformation.shared.formStatus == .available,
              ConsentInformation.shared.consentStatus == .required else { return }
        await withCheckedContinuation { continuation in
            ConsentForm.loadAndPresentIfRequired(from: viewController) { _ in
                continuation.resume()
            }
        }
    }

    private func requestATTIfNeeded() async {
        guard #available(iOS 14, *) else { return }
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            ATTrackingManager.requestTrackingAuthorization { _ in
                continuation.resume()
            }
        }
    }

    private func beginAdInitializationIfNeeded() {
        guard adInitializationTask == nil else { return }
        adInitializationTask = Task { @MainActor [self] in
            await startMobileAds()
            isAdSdkReady = true
            RewardedAdService.shared.loadAd(for: .shieldUnlock)
        }
    }

    private func startMobileAds() async {
        #if DEBUG
        // Debug 빌드에서만 개발자 기기를 테스트 기기로 등록한다. Release에서는 모든 기기에 실제 광고가 노출된다.
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = ["b5ed086b1fad2b5c424eb682be84e562"]
        #endif
        await withCheckedContinuation { continuation in
            MobileAds.shared.start { _ in continuation.resume() }
        }
    }
}
