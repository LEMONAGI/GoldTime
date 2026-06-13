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

        /// 쿨다운 종료 시각 맵(`cooldownUntilByGroupID`)에 미래 항목이 하나라도 있으면
        /// 휴식 중인 잠금이 포함된 상태. SharedStore를 끌어오지 않고 원시 UserDefaults만 읽는다.
        static var hasActiveCooldown: Bool {
            guard let data = defaults.data(forKey: "cooldownUntilByGroupID"),
                  let raw = try? JSONDecoder().decode([String: Date].self, from: data) else {
                return false
            }
            let now = Date()
            return raw.values.contains { $0 > now }
        }
    }

    private let shieldMessages = [
        "오늘 한도 다 썼어요.",
        "지금 나가면 광고는 없어요.",
        "더 쓰려면 광고가 필요해요.",
        "광고 없이 나가는 방법도 있어요.",
        "멈추거나, 광고를 보거나."
    ]

    private let cooldownMessages = [
        "쉬는 시간이에요.",
        "잠깐 쉬었다 가요.",
        "더 쓰려면 광고가 필요해요.",
        "광고 없이 기다리는 방법도 있어요.",
        "기다리거나, 광고를 보거나."
    ]

    private func makeConfiguration() -> ShieldConfiguration {
        if OpenRequestStore.isPending {
            return makeOpenRequestConfiguration()
        }

        // 휴식 중인 잠금이 있으면 "한도 초과"가 아니라 쿨다운 문구로 바꾼다.
        let pool = OpenRequestStore.hasActiveCooldown ? cooldownMessages : shieldMessages
        let title = pool.randomElement() ?? "오늘 한도를 다 썼어요."
        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            backgroundColor: UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 0.85),
            icon: nil,
            title: ShieldConfiguration.Label(
                text: title,
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "더 쓰려면 GoldTime에서 선택하세요.",
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
                text: "알림이 오지 않는다면\n다시 알림 보내기를 누르거나,\n방해금지 모드를 확인하세요.",
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
