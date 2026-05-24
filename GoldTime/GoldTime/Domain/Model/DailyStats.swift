
import Foundation

struct DailyStats: Codable, Equatable, Identifiable {
    static let estimatedWonPerAd = 100

    var dateKey: String
    var adWatchCount: Int
    var adUnlockedSeconds: Int
    var oneMinuteUsedCount: Int
    var shieldHitCount: Int
    var walkAwayCount: Int

    init(
        dateKey: String,
        adWatchCount: Int = 0,
        adUnlockedSeconds: Int = 0,
        oneMinuteUsedCount: Int = 0,
        shieldHitCount: Int = 0,
        walkAwayCount: Int = 0
    ) {
        self.dateKey = dateKey
        self.adWatchCount = adWatchCount
        self.adUnlockedSeconds = adUnlockedSeconds
        self.oneMinuteUsedCount = oneMinuteUsedCount
        self.shieldHitCount = shieldHitCount
        self.walkAwayCount = walkAwayCount
    }

    var id: String { dateKey }

    var date: Date {
        Self.date(fromDateKey: dateKey) ?? .distantPast
    }

    var totalUnlockedSeconds: Int {
        adUnlockedSeconds + oneMinuteUsedCount * 60
    }

    var estimatedAdRevenueWon: Int {
        adWatchCount * Self.estimatedWonPerAd
    }

    static func dateKey(for date: Date) -> String {
        dateKeyFormatter.string(from: date)
    }

    static func date(fromDateKey key: String) -> Date? {
        dateKeyFormatter.date(from: key)
    }

    private static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
