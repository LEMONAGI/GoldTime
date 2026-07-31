//
//  LockFeedback.swift
//  GoldTime
//
//  연장 불가 기간이 확정되는 순간의 "잠겼다" 피드백. 광고 연장의 결제감(`PurchaseFeedback`)과
//  짝을 이룬다 — 한쪽은 사서 여는 감각, 이쪽은 닫아 거는 감각.
//
//  ── 왜 소리가 없는가 (되돌리기 전에 읽을 것) ──────────────────────────────────
//  실기기 청취로 전부 기각했다(2026-07-30~31): iOS 시스템 사운드 1306(너무 낮고 짧아 알럿이
//  뜨는 순간에 인지 자체가 안 됨) → 1160 단음 → 1160+1407 시퀀스 → 번들 음원 7종
//  (Freesound CC0 자물쇠·열쇠·문 잠금 계열). 시스템 사운드는 알림·키보드·카메라용이라
//  "잠기는" 감각을 담당하는 항목이 없고, 실제 문/자물쇠 녹음은 알럿이 뜨며 화면이 전환되는
//  0.5초짜리 순간에 얹으면 하나같이 이질적이었다.
//
//  그래서 **촉각만으로** 간다. 잠금은 iOS 안에서도 원래 촉각이 담당하는 영역이고, 무음
//  스위치를 켠 사용자에게도 동일하게 전달된다는 이점이 있다. 세 이벤트가 촉각으로 구분된다:
//    · 잠글 때 — 묵직한 두 박 (담담한 확정)
//    · 광고로 풀 때 — `PurchaseFeedback` 사운드 + success 햅틱 (결제감)
//  소리를 다시 넣자는 제안이 나오면 위 기각 이력을 먼저 확인할 것.
//

import UIKit

enum LockFeedback {
    /// 리듬 한 박 — 세기와 다음 박까지의 간격.
    private struct Beat {
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        let intensity: CGFloat
        let gapMillis: Int
    }

    /// 확정 순간의 리듬 — **툭 · 툭**, 묵직한 두 박(2026-07-31 실기기 청취로 채택).
    ///
    /// 후보 비교 이력: 툭·투툭 / 촘촘한 툭·투툭 / 투툭·툭 / 균등 3연타 / **툭·툭**.
    /// 3박 계열은 리듬이 화려해서 "확정"보다 "알림"처럼 읽혔고, 두 박이 가장 담담했다 —
    /// 최종 확인 문구를 "정말 잠글까요?"에서 "설정할까요?"로 낮춘 톤(`658f884`)과 같은 방향이다.
    /// 간격 150ms는 두 박이 별개로 들리면서도 한 동작으로 묶이는 지점이다(더 짧으면 한 번의
    /// 떨림으로 뭉개지고, 더 길면 두 사건으로 분리된다).
    private static let lockBeats: [Beat] = [
        Beat(style: .heavy, intensity: 1.0, gapMillis: 150),
        Beat(style: .heavy, intensity: 1.0, gapMillis: 0),
    ]

    /// 연장 불가 확정 알럿이 뜨는 순간 호출.
    ///
    /// 호출부가 동기 컨텍스트(`ContentViewModel.confirmStrictLock`)라 `Task`로 감싼다 —
    /// 박 사이 간격 때문에 재생 자체는 비동기일 수밖에 없다. **첫 박은 즉시** 나가므로
    /// 알럿이 뜨는 타이밍과 어긋나지 않는다.
    @MainActor
    static func play() {
        Task { await perform(lockBeats) }
    }

    /// 박자 재생. 스타일별 generator를 **미리 만들어 `prepare()`** 한다 —
    /// 매 박마다 새로 만들면 하드웨어 준비 지연으로 첫 박이 뭉개져 리듬이 무너진다.
    @MainActor
    private static func perform(_ beats: [Beat]) async {
        var generators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
        for beat in beats where generators[beat.style] == nil {
            let generator = UIImpactFeedbackGenerator(style: beat.style)
            generator.prepare()
            generators[beat.style] = generator
        }

        for beat in beats {
            generators[beat.style]?.impactOccurred(intensity: beat.intensity)
            guard beat.gapMillis > 0 else { continue }
            try? await Task.sleep(for: .milliseconds(beat.gapMillis))
        }
    }
}
