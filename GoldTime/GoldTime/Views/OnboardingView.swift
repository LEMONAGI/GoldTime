//
//  OnboardingView.swift
//  GoldTime
//
//  최초 실행 시 Family Controls 권한 요청 화면.
//

import SwiftUI

struct OnboardingView: View {
    let onAuthorized: () -> Void

    @State private var auth = AuthorizationService.shared
    @State private var errorMessage: String?
    @State private var isRequesting = false

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
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button {
                Task { await requestAuthorization() }
            } label: {
                Text(isRequesting ? "권한 요청 중..." : "스크린타임 권한 허용하기")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GoldTimeButtonStyle(background: Color.accent, foreground: .black, cornerRadius: 12))
            .disabled(isRequesting)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    private func requestAuthorization() async {
        isRequesting = true
        defer { isRequesting = false }
        do {
            try await auth.request()
            await NotificationService.requestAuthorizationIfNeeded()
            if auth.isAuthorized {
                onAuthorized()
            } else {
                errorMessage = "권한이 필요해요. 설정에서 스크린타임 권한을 허용해주세요."
            }
        } catch {
            errorMessage = "권한 요청 실패: \(error.localizedDescription)"
        }
    }
}
