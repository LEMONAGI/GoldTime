//
//  PurchaseFeedback.swift
//  GoldTime
//
//  광고 연장(= 시간 구매) 완료 순간의 결제감 피드백.
//

import AudioToolbox
import UIKit

enum PurchaseFeedback {
    /// 광고 연장 완료 알럿이 뜨는 순간 호출. 공개 시스템 차임 + 성공 햅틱으로 "결제했다"는 감각을 강조한다.
    /// 사운드는 무음 스위치를 따르므로(무음 모드에선 안 남) 햅틱을 항상 함께 준다.
    @MainActor
    static func play() {
        AudioServicesPlaySystemSound(1407) // 올라가는 완료 차임. 결제감이 약하면 다른 공개 ID로 교체 가능.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
