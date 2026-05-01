//
//  AdMockView.swift
//  GoldTime
//
//  10초 ProgressView 광고 모킹. 추후 GADRewardedAd 로 교체.
//

import SwiftUI

struct AdMockView: View {
    let durationSeconds: Double = 10
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var elapsed: Double = 0
    @State private var task: Task<Void, Never>?

    private var progress: Double {
        min(elapsed / durationSeconds, 1.0)
    }

    private var remainingSeconds: Int {
        max(0, Int(durationSeconds - elapsed.rounded(.down)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Text("📺")
                    .font(.system(size: 64))
                Text("광고 시청 중...")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.yellow)
                    .padding(.horizontal, 48)
                Text("\(remainingSeconds)초 남음")
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("취소", role: .cancel) {
                    task?.cancel()
                    onCancel()
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 32)
            }
        }
        .task {
            task = Task {
                let tickInterval: Double = 0.05
                while elapsed < durationSeconds {
                    try? await Task.sleep(for: .milliseconds(Int(tickInterval * 1000)))
                    if Task.isCancelled { return }
                    elapsed += tickInterval
                }
                if !Task.isCancelled {
                    onComplete()
                }
            }
            await task?.value
        }
    }
}
