//
//  LockOptionsView.swift
//  GoldTime
//
//  쉴드가 활성화된 상태에서 앱 진입 시 표시되는 그룹별 연장 화면.
//

import FamilyControls
import Foundation
import ManagedSettings
import SwiftUI

struct LockOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = LockOptionsViewModel()
    let initialGroupID: UUID?

    init(initialGroupID: UUID? = nil) {
        self.initialGroupID = initialGroupID
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("💰").font(.system(size: 56))
                Text("시간이 금이다")
                    .font(.title.bold())
                Text(viewModel.headerMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)

            groupContext

            Spacer()

            VStack(spacing: 12) {
                optionButton(
                    title: "그만 쓰기",
                    subtitle: Text("광고 없이 종료").foregroundColor(.green),
                    background: Color.gray.opacity(0.2),
                    foreground: .primary,
                    enabled: true,
                    action: {
                        if viewModel.tapWalkAway() {
                            dismiss()
                        }
                    }
                )

                optionButton(
                    title: "1분만 더 쓰기",
                    subtitle: oneMinuteSubtitle,
                    background: viewModel.canExtendOneMinute ? Color.accent : Color.gray.opacity(0.3),
                    foreground: viewModel.canExtendOneMinute ? .black : .gray,
                    enabled: viewModel.canExtendOneMinute,
                    action: viewModel.tapOneMinute
                )

                optionButton(
                    title: "광고 보고 15분 더 쓰기",
                    subtitle: adSubtitle,
                    background: viewModel.canExtendWithAd ? Color.accent : Color.gray.opacity(0.3),
                    foreground: viewModel.canExtendWithAd ? .black : .gray,
                    enabled: viewModel.canExtendWithAd,
                    action: viewModel.startAdFlow
                )
            }
            .padding(.horizontal, 20)

            if let infoMessage = viewModel.infoMessage {
                Text(infoMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            if viewModel.canRetryRelockRegistration {
                Button("다시 시도") {
                    viewModel.retryRelockRegistration()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .onAppear {
            viewModel.onAppear(initialGroupID: initialGroupID)
        }
        .fullScreenCover(isPresented: $viewModel.isRewardedAdPresented, onDismiss: {
            viewModel.rewardedAdDismissed()
        }) {
            RewardedAdView(
                onComplete: viewModel.rewardedAdDidComplete,
                onCancel: viewModel.rewardedAdDidCancel
            )
        }
        .alert(item: $viewModel.completionAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("확인")) {
                    dismiss()
                }
            )
        }
        .interactiveDismissDisabled()
    }

    private var oneMinuteSubtitle: Text {
        if viewModel.oneMinuteRemaining > 0 {
            var str = AttributedString("무료")
            str.swiftUI.foregroundColor = .green
            str += AttributedString(" · 오늘 \(viewModel.oneMinuteRemaining)번 남음")
            return Text(str)
        } else {
            return Text("오늘은 더 사용할 수 없어요").foregroundColor(.red.opacity(0.8))
        }
    }

    private var adSubtitle: Text {
        if let name = viewModel.selectedGroupName {
            var str = AttributedString("광고 1회")
            str.swiftUI.foregroundColor = .red
            str += AttributedString(" · \(name) 15분 연장")
            return Text(str)
        } else {
            return Text("풀 그룹을 먼저 고르세요").foregroundColor(.orange)
        }
    }

    @ViewBuilder
    private var groupContext: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.lockedGroups.isEmpty {
                Text("잠긴 그룹을 찾지 못했어요.")
                    .font(.headline)
                Text("앱을 다시 열어보거나, GoldTime에서 모니터링 상태를 확인해주세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if viewModel.lockedGroups.count == 1, let group = viewModel.lockedGroups.first {
                Text(group.displayName)
                    .font(.headline)
                Text("이 그룹만 한 번 연장할 수 있어요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("잠긴 그룹이 여러 개예요")
                    .font(.headline)
                Text("한 번에 한 그룹만 연장합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(viewModel.lockedGroups) { group in
                        Button {
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) {
                                viewModel.selectGroup(group.id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.displayName)
                                        .font(.subheadline.weight(.semibold))
                                    Text("항목 \(group.selectionCount)/\(viewModel.maxAppsPerGroup) · \(group.dailyLimitMinutes)분 한도")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: viewModel.selectedGroupID == group.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(viewModel.selectedGroupID == group.id ? Color.accent : .secondary)
                            }
                            .rowContainer()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardContainer()
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func optionButton(
        title: String,
        subtitle: Text,
        background: Color,
        foreground: Color,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                subtitle
                    .font(.subheadline)
                    .opacity(0.8)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!enabled)
    }
}
