//
//  ShieldConfigurationExtension.swift
//  ShieldConfigurationExtension
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private let shieldMessages = [
        "오늘 한도를 다 썼어요.",
        "여기서 멈추면 광고는 없습니다.",
        "더 쓰려면 광고가 필요해요.",
        "잠깐 쉬어갈 시간이에요.",
        "멈추거나, 광고를 보거나."
    ]

    private func makeConfiguration() -> ShieldConfiguration {
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
