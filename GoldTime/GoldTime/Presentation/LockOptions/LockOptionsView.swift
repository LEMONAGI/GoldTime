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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                header

                groupContext

                optionStack

                if let infoMessage = viewModel.infoMessage {
                    Text(infoMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                }

                if viewModel.canRetryRelockRegistration {
                    Button("다시 시도") {
                        viewModel.retryRelockRegistration()
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
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

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 64, height: 64)
                .background(Color.accent.opacity(0.14))
                .clipShape(Circle())

            VStack(spacing: 6) {
                Text("한도 끝났어요")
                    .font(.title2.bold())
                Text(viewModel.headerMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var optionStack: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("선택")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            walkAwayButton

            VStack(spacing: 10) {
                extensionOptionButton(
                    systemName: "timer",
                    title: "1분만 더 쓰기",
                    subtitle: oneMinuteSubtitle,
                    enabled: viewModel.canExtendOneMinute,
                    action: viewModel.tapOneMinute
                )

                extensionOptionButton(
                    systemName: "play.rectangle",
                    title: "광고 보고 15분 더 쓰기",
                    subtitle: adSubtitle,
                    enabled: viewModel.canExtendWithAd,
                    action: viewModel.startAdFlow
                )
            }
        }
        .padding(.top, 10)
    }

    private var walkAwayButton: some View {
        Button {
            if viewModel.tapWalkAway() {
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "power")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("그만 쓰기")
                        .font(.subheadline.weight(.semibold))
                    Text("광고 없이 종료")
                        .font(.footnote)
                        .foregroundStyle(.black.opacity(0.72))
                }

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 14)
            .background(Color.accent)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("그만 쓰기, 광고 없이 종료")
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
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.lockedGroups.isEmpty {
                Text("잠긴 그룹을 찾지 못했어요.")
                    .font(.subheadline.weight(.semibold))
                Text("앱을 다시 열어보거나, GoldTime에서 모니터링 상태를 확인해주세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if viewModel.lockedGroups.count == 1, let group = viewModel.lockedGroups.first {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        groupTitle(for: group)
                        groupTokenIcons(for: group)
                    }
                    Spacer(minLength: 8)
                }
                .rowContainer()
            } else {
                Text("잠긴 그룹이 여러 개예요")
                    .font(.subheadline.weight(.semibold))
                Text("한 번에 한 그룹만 연장합니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.lockedGroups) { group in
                            Button {
                                var t = Transaction()
                                t.disablesAnimations = true
                                withTransaction(t) {
                                    viewModel.selectGroup(group.id)
                                }
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        groupTitle(for: group)
                                        groupTokenIcons(for: group)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: viewModel.selectedGroupID == group.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(viewModel.selectedGroupID == group.id ? Color.accent : .secondary)
                                        .frame(width: 22, height: 22)
                                }
                                .rowContainer()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardContainer(padding: 14)
    }

    private func groupTitle(for group: ScreenTimeGroup) -> some View {
        HStack(spacing: 6) {
            Text(group.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("\(group.selectionCount)/9")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func groupTokenIcons(for group: ScreenTimeGroup) -> some View {
        if group.selectionCount == 0 {
            Text("항목 없음")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                ForEach(
                    group.selection.applicationTokens.sorted(by: tokenSort),
                    id: \.self
                ) { token in
                    Label(token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(0.95)
                        .frame(width: 20, height: 20)
                }
                ForEach(
                    group.selection.webDomainTokens.sorted(by: tokenSort),
                    id: \.self
                ) { token in
                    Label(token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(0.95)
                        .frame(width: 20, height: 20)
                }
            }
        }
    }

    private func tokenSort<T: Encodable>(_ lhs: T, _ rhs: T) -> Bool {
        ((try? JSONEncoder().encode(lhs)) ?? Data())
            .lexicographicallyPrecedes((try? JSONEncoder().encode(rhs)) ?? Data())
    }

    @ViewBuilder
    private func extensionOptionButton(
        systemName: String,
        title: String,
        subtitle: Text,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(enabled ? Color.accent : .secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    subtitle
                        .font(.footnote)
                        .opacity(0.86)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 14)
            .background(Color(.secondarySystemGroupedBackground))
            .foregroundStyle(enabled ? Color.primary : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(enabled ? 0.08 : 0.04))
            }
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.58)
    }
}
