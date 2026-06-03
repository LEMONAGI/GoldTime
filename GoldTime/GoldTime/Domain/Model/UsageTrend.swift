
import Foundation

/// 추가 사용 시간이 연속으로 같은 방향(감소/증가)으로 움직인 구간을 나타냅니다.
/// 엄격 연속 기준: 직전 기간보다 줄면 감소, 늘면 증가, 같으면 흐름이 끊깁니다.
struct UsageTrend: Equatable {
    let direction: TrendDirection
    /// 같은 방향으로 연속된 변화 횟수. flat이면 0.
    let streak: Int

    /// 오래된→최신 순서의 기간별 합계로 추세를 계산합니다.
    /// 비교할 기간이 2개 미만이면 nil을 반환합니다.
    static func fromOrderedTotals(_ totals: [Int]) -> UsageTrend? {
        guard totals.count >= 2 else { return nil }

        func sign(_ value: Int) -> Int {
            if value > 0 { return 1 }
            if value < 0 { return -1 }
            return 0
        }

        let last = totals.count - 1
        let direction = sign(totals[last] - totals[last - 1])
        if direction == 0 {
            return UsageTrend(direction: .flat, streak: 0)
        }

        var streak = 0
        var index = last
        while index >= 1, sign(totals[index] - totals[index - 1]) == direction {
            streak += 1
            index -= 1
        }

        return UsageTrend(direction: direction > 0 ? .up : .down, streak: streak)
    }
}
