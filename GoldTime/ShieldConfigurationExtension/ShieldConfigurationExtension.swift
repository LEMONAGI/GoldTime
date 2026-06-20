//
//  ShieldConfigurationExtension.swift
//  ShieldConfigurationExtension
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private enum OpenRequestStore {
        static let suiteName = "group.com.goldtime.shared"
        static let startedAtKey = "shieldOpenRequestStartedAt"
        static let pendingWindow: TimeInterval = 30

        static var defaults: UserDefaults {
            UserDefaults(suiteName: suiteName) ?? .standard
        }

        static var isPending: Bool {
            guard let startedAt = defaults.object(forKey: startedAtKey) as? Date else {
                return false
            }
            return Date().timeIntervalSince(startedAt) <= pendingWindow
        }
    }

    /// 잠금 모드(일일 한도·시간대 차단·쿨다운)와 무관하게 쓰는 모드 중립 문구 풀.
    /// extension은 막힌 앱이 어느 모드인지 알 수 없으므로(타겟에 SharedStore 없음) 모드 특정
    /// 표현 대신 세 모드 공통 분모(막혀 있고·내가 정했고·더 쓰려면 광고)만 담아 단일화한다.
    private let shieldMessages = [
        String(localized: "shield.message.decided"),
        String(localized: "shield.message.timeToStop"),
        String(localized: "shield.message.needAd"),
        String(localized: "shield.message.stopWithoutAd"),
        String(localized: "shield.message.stopOrAd")
    ]

    private func makeConfiguration() -> ShieldConfiguration {
        if OpenRequestStore.isPending {
            return makeOpenRequestConfiguration()
        }

        let title = shieldMessages.randomElement() ?? String(localized: "shield.message.timeToStop")
        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            backgroundColor: UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 0.85),
            icon: nil,
            title: ShieldConfiguration.Label(
                text: title,
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: String(localized: "shield.subtitle.chooseInApp"),
                color: UIColor.white.withAlphaComponent(0.85)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: String(localized: "shield.button.stop"),
                color: .black
            ),
            primaryButtonBackgroundColor: UIColor(red: 245 / 255, green: 197 / 255, blue: 24 / 255, alpha: 1.0),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: String(localized: "shield.button.openApp"),
                color: .white
            )
        )
    }

    private func makeOpenRequestConfiguration() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            backgroundColor: UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 0.9),
            icon: nil,
            title: ShieldConfiguration.Label(
                text: String(localized: "shield.openRequest.title"),
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: String(localized: "shield.openRequest.subtitle"),
                color: UIColor.white.withAlphaComponent(0.72)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: String(localized: "shield.button.stop"),
                color: .black
            ),
            primaryButtonBackgroundColor: UIColor(red: 245 / 255, green: 197 / 255, blue: 24 / 255, alpha: 1.0),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: String(localized: "shield.openRequest.resend"),
                color: .white
            )
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }
}
