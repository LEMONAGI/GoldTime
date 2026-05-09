//
//  GoldTimeTests.swift
//  GoldTimeTests
//
//  Created by YunhakLee on 5/2/26.
//

import Testing
@testable import GoldTime

struct GoldTimeTests {

    @Test func estimatedRevenueUsesConfiguredAdPrice() {
        let stats = SharedStore.DailyStats(
            dateKey: "2026-05-09",
            adWatchCount: 3,
            adUnlockedSeconds: 15 * 60,
            oneMinuteUsedCount: 2,
            shieldHitCount: 1
        )

        #expect(stats.estimatedAdRevenueWon == 300)
        #expect(stats.totalUnlockedSeconds == 17 * 60)
    }

    @Test func recordsTodayDashboardStats() {
        SharedStore.clearDailyStatsForTesting()
        defer { SharedStore.clearDailyStatsForTesting() }

        SharedStore.recordAdUnlock(seconds: 15 * 60)
        SharedStore.recordOneMinuteUnlock(seconds: 60)
        SharedStore.recordShieldHit()

        let stats = SharedStore.todayStats
        #expect(stats.adWatchCount == 1)
        #expect(stats.adUnlockedSeconds == 15 * 60)
        #expect(stats.oneMinuteUsedCount == 1)
        #expect(stats.shieldHitCount == 1)
        #expect(stats.estimatedAdRevenueWon == 100)
    }

}
