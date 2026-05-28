//
//  ReviewRequestService.swift
//  GoldTime
//

import StoreKit
import UIKit

enum ReviewRequestService {
    private static let lastRequestKey = "lastReviewRequestDate"
    private static let minIntervalDays = 90

    /// 완전한 한 주 데이터가 있는 주의 첫날(월요일) 앱 포그라운드 진입 시 리뷰 요청.
    /// Apple의 연 3회 제한에 더해 90일 간격을 코드에서도 보장한다.
    @MainActor
    static func requestIfEligible() {
        guard isWeekStartToday,
              hasCompletedFullWeek,
              !requestedRecently else { return }

        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }

        AppStore.requestReview(in: scene)
        UserDefaults.standard.set(Date(), forKey: lastRequestKey)
    }

    // 오늘이 주의 시작일(기본: 월요일 = weekday 2)인지
    private static var isWeekStartToday: Bool {
        Calendar.current.component(.weekday, from: Date()) == SharedStore.weekStartDay
    }

    // oldestStatDate가 지난 주 시작일 이전이면 완전한 한 주 데이터가 존재
    private static var hasCompletedFullWeek: Bool {
        guard let oldest = SharedStore.oldestStatDate else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        guard let prevWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: today) else { return false }
        return oldest <= prevWeekStart
    }

    private static var requestedRecently: Bool {
        guard let last = UserDefaults.standard.object(forKey: lastRequestKey) as? Date else { return false }
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        return days < minIntervalDays
    }
}
