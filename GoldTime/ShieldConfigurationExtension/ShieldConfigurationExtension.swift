//
//  ShieldConfigurationExtension.swift
//  ShieldConfigurationExtension
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private func makeConfiguration() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            backgroundColor: UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 0.85),
            icon: nil,
            title: ShieldConfiguration.Label(
                text: "시간이 금이다 ⏳",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "오늘 한도를 다 썼어요.\n홈으로 나가서 GoldTime을 열어주세요.",
                color: UIColor.white.withAlphaComponent(0.85)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "잘 참았어요",
                color: .black
            ),
            primaryButtonBackgroundColor: UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "GoldTime 가기",
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
