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

    private init() {}

    /// UMP 동의 → ATT → MobileAds.start() 순서를 보장하는 전체 흐름.
    /// 동의 거부, 네트워크 없음 등 어떤 경우에도 MobileAds.start()까지 완료한다.
    func requestConsentAndInitialize() async {
        await requestATTIfNeeded()
        await startMobileAds()
        isAdSdkReady = true
        RewardedAdService.shared.loadAd()
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

    private func startMobileAds() async {
        // 등록된 개발자 기기는 빌드 구성과 무관하게 항상 테스트 광고로 보호한다.
        // (self-click으로 인한 invalid traffic 방지. 일반 사용자에게는 실제 광고가 노출된다.)
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = ["b5ed086b1fad2b5c424eb682be84e562"]
        await withCheckedContinuation { continuation in
            MobileAds.shared.start { _ in continuation.resume() }
        }
    }
}
