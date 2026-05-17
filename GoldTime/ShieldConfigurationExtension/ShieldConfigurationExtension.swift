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

    private let shieldMessages = [
        "오늘 한도를 다 썼어요.",
        "여기서 멈추면 광고는 없습니다.",
        "더 쓰려면 광고가 필요해요.",
        "잠깐 쉬어갈 시간이에요.",
        "멈추거나, 광고를 보거나."
    ]

    private func makeConfiguration() -> ShieldConfiguration {
        if OpenRequestStore.isPending {
            return makeOpenRequestConfiguration()
        }

        let title = shieldMessages.randomElement() ?? "오늘 한도를 다 썼어요."
        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            backgroundColor: UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 0.85),
            icon: nil,
            title: ShieldConfiguration.Label(
                text: title,
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "GoldTime을 열어 다음 행동을 선택하세요.",
                color: UIColor.white.withAlphaComponent(0.85)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "그만 쓰기",
                color: .black
            ),
            primaryButtonBackgroundColor: UIColor(red: 245 / 255, green: 197 / 255, blue: 24 / 255, alpha: 1.0),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "GoldTime 열기",
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
                text: "위의 GoldTime 알림을 눌러주세요",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "알림을 탭하면 1분 연장 또는 광고 시청을 선택할 수 있어요. 늦게 오면 다시 알림 보내기를 눌러주세요.",
                color: UIColor.white.withAlphaComponent(0.72)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "그만 쓰기",
                color: .black
            ),
            primaryButtonBackgroundColor: UIColor(red: 245 / 255, green: 197 / 255, blue: 24 / 255, alpha: 1.0),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "다시 알림 보내기",
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
