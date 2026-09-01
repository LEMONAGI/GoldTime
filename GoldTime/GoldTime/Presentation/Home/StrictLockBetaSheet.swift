//
//  StrictLockBetaSheet.swift
//  GoldTime
//
//  "연장 불가 모드 베타 출시" 안내 시트. 홈 상단 확성기 배너를 누르면 열린다.
//  과거 홈 진입마다 강제로 뜨던 `.alert`(제목 + 본문 + 확인)을 대체 — 같은 문구를 시트로 보여준다.
//

import SwiftUI

struct StrictLockBetaSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("home.strictLockBeta.title")
                    .font(.title2.bold())
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 24)

                Text("home.strictLockBeta.message")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            // 배경(.bar 등)을 두지 않아 버튼 영역이 시트 배경과 같은 색으로 자연스럽게 이어진다.
            Button {
                dismiss()
            } label: {
                Text("common.confirm")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GoldTimeButtonStyle(background: Color.accent, foreground: .black))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    Color(.systemGroupedBackground)
        .sheet(isPresented: .constant(true)) { StrictLockBetaSheet() }
}

#Preview("EN") {
    Color(.systemGroupedBackground)
        .sheet(isPresented: .constant(true)) {
            StrictLockBetaSheet().environment(\.locale, .init(identifier: "en"))
        }
}

#Preview("JA") {
    Color(.systemGroupedBackground)
        .sheet(isPresented: .constant(true)) {
            StrictLockBetaSheet().environment(\.locale, .init(identifier: "ja"))
        }
}
