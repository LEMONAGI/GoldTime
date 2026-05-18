//
//  OnboardingView.swift
//  GoldTime
//
//  최초 실행 시 Family Controls 권한 요청 화면.
//

import SwiftUI

struct OnboardingView: View {
    @State private var viewModel: OnboardingViewModel

    init(onAuthorized: @escaping () -> Void) {
        _viewModel = State(initialValue: OnboardingViewModel(onAuthorized: onAuthorized))
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("💰")
                .font(.system(size: 80))
            Text("시간이 금이다")
                .font(.largeTitle.bold())
            Text("한도를 넘기면 선택한 앱이 잠기고,\n더 쓰려면 광고를 봐야 해요.\n조금 불편하게 만들어두겠습니다.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button {
                Task { await viewModel.requestAuthorization() }
            } label: {
                Text(viewModel.isRequesting ? "권한 요청 중..." : "스크린타임 권한 허용하기")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GoldTimeButtonStyle(background: Color.accent, foreground: .black, cornerRadius: 12))
            .disabled(viewModel.isRequesting)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}
