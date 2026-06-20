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

    /// EEA/UK 등 동의 관리가 필요한 지역에서만 true. 설정 화면에서 "광고/개인정보 설정"
    /// 행을 노출할지 결정하는 데 쓴다. 비대상 지역은 false라 행 자체가 숨겨진다.
    var isPrivacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    /// 사용자가 설정에서 명시적으로 동의를 변경/철회할 때 UMP privacy options 폼을 다시 띄운다.
    /// 온보딩 흐름(`consentFlowTask`)과 달리 사용자 명시 액션이므로 단일 Task 큐를 거치지 않고
    /// 매번 즉시 표시한다(설정 진입 시점엔 이미 온보딩이 끝나 동의 정보가 로드돼 있다).
    func presentPrivacyOptions() async {
        await presentPrivacyOptions(from: findPresentingViewController())
    }

    func presentPrivacyOptions(from viewController: UIViewController) async {
        await withCheckedContinuation { continuation in
            ConsentForm.presentPrivacyOptionsForm(from: viewController) { _ in
                continuation.resume()
            }
        }
    }

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
