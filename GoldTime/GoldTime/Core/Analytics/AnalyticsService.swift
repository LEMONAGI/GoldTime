//
//  AnalyticsService.swift
//  GoldTime
//

import Foundation
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics

/// Firebase Analytics / Crashlytics 얇은 래퍼.
///
/// - Core 레이어 서비스이므로 Firebase를 직접 import 한다(Domain/Presentation에서 직접 참조 금지,
///   `AnalyticsRepository` 프로토콜 경유).
/// - **메인 앱 타겟 전용**: extension 타겟에는 이 파일을 포함하지 않는다(Firebase 미링크).
///   extension에서 발생한 이벤트는 `SharedStore`의 대기 큐에 쌓고 메인 앱이 드레인해 전송한다.
/// - 이벤트 이름/파라미터는 호출부에서 자유 문자열로 넘기지 말고 `AnalyticsEvent`(Domain)로
///   타입 안전하게 구성한다.
final class AnalyticsService {
    static let shared = AnalyticsService()

    private init() {}

    /// 앱 구동 시 1회. 모든 Analytics 호출보다 먼저 실행되어야 한다.
    func configure() {
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
    }

    func logEvent(name: String, parameters: [String: Any]?) {
        Analytics.logEvent(name, parameters: parameters)
    }

    func setUserProperty(_ value: String?, for name: String) {
        Analytics.setUserProperty(value, forName: name)
    }

    /// 비치명적 오류 기록(Crashlytics non-fatal). 충돌은 아니지만 추적하고 싶은 실패에 사용.
    func recordError(_ error: Error, context: String) {
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(context, forKey: "context")
        crashlytics.record(error: error)
    }

    /// 동의 기반 수집을 원할 때 토글. 기본은 켜짐(Info.plist/SDK 기본값).
    func setCollectionEnabled(_ enabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(enabled)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(enabled)
    }
}
