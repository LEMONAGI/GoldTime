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
            Text("⏳")
                .font(.system(size: 80))
            Text("시간이 금이다")
                .font(.largeTitle.bold())
            Text("스크린타임 한도를 설정하면\n선택한 앱이 자동으로 잠겨요.\n그리고 광고를 봐야만 다시 풀 수 있어요.")
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
                Text(isRequesting ? "요청 중..." : "스크린타임 권한 허용하기")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.yellow)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
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
                errorMessage = "권한을 받지 못했어요. 설정에서 허용해주세요."
            }
        } catch {
            errorMessage = "권한 요청 실패: \(error.localizedDescription)"
        }
    }
}
