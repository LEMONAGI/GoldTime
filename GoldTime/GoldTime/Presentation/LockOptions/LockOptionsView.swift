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
                    Button("common.retry") {
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
                placement: .shieldUnlock,
                onComplete: viewModel.rewardedAdDidComplete,
                onCancel: viewModel.rewardedAdDidCancel
            )
        }
        .alert(item: $viewModel.completionAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("common.confirm")) {
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
                Text(viewModel.headerTitle)
                    .font(.title2.bold())
                Text(viewModel.headerMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let caption = viewModel.selectedWindowLockCaption ?? viewModel.selectedCooldownLockCaption {
                    Text(caption)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var optionStack: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("lock.section.choose")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            walkAwayButton

            if let notice = viewModel.nearMidnightNotice {
                nearMidnightNoticeBanner(notice)
            }

            VStack(spacing: 10) {
                extensionOptionButton(
                    systemName: "timer",
                    title: String(localized: "lock.option.oneMinute"),
                    subtitle: oneMinuteSubtitle,
                    enabled: viewModel.canExtendOneMinute,
                    action: viewModel.tapOneMinute
                )

                extensionOptionButton(
                    systemName: "play.rectangle",
                    title: viewModel.adButtonTitle,
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
                    Text("lock.walkAway.title")
                        .font(.subheadline.weight(.semibold))
                    Text("lock.walkAway.subtitle")
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
        .accessibilityLabel(Text("lock.walkAway.a11y"))
    }

    private var oneMinuteSubtitle: Text {
        if viewModel.isNearMidnightCutoff {
            return Text("lock.subtitle.nearMidnightOneMinute").foregroundColor(.secondary)
        }
        if viewModel.oneMinuteRemaining > 0 {
            var str = AttributedString(String(localized: "lock.free"))
            str.swiftUI.foregroundColor = .green
            str += AttributedString(String(localized: "lock.oneMinuteRemaining \(viewModel.oneMinuteRemaining)"))
            return Text(str)
        } else {
            return Text("lock.subtitle.exhausted").foregroundColor(.red.opacity(0.8))
        }
    }

    private var adSubtitle: Text {
        guard let name = viewModel.selectedGroupName else {
            return Text("lock.subtitle.pickGroup").foregroundColor(.orange)
        }
        if viewModel.isNearMidnightCutoff {
            var str = AttributedString(String(localized: "lock.adOnce"))
            str.swiftUI.foregroundColor = .red
            str += AttributedString(String(localized: "lock.adSubtitle.untilMidnight \(name)"))
            return Text(str)
        }
        var str = AttributedString(String(localized: "lock.adOnce"))
        str.swiftUI.foregroundColor = .red
        str += AttributedString(String(localized: "lock.adSubtitle.10min \(name)"))
        return Text(str)
    }

    private func nearMidnightNoticeBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "moon.stars")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var groupContext: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.lockedGroups.isEmpty {
                Text("lock.noGroups.title")
                    .font(.subheadline.weight(.semibold))
                Text("lock.noGroups.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if viewModel.lockedGroups.count == 1, let group = viewModel.lockedGroups.first {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 10) {
                        groupTitle(for: group)
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                    groupTokenIcons(for: group)
                }
                .padding(.bottom, 12)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text("lock.multiGroups.title")
                    .font(.subheadline.weight(.semibold))
                Text("lock.multiGroups.subtitle")
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
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .center, spacing: 10) {
                                        groupTitle(for: group)
                                        Spacer(minLength: 8)
                                        Image(systemName: viewModel.selectedGroupID == group.id ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(viewModel.selectedGroupID == group.id ? Color.accent : .secondary)
                                            .frame(width: 22, height: 22)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.top, 12)

                                    groupTokenIcons(for: group)
                                }
                                .padding(.bottom, 12)
                                .background(Color(.tertiarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
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
                .minimumScaleFactor(0.7)
            Text("\(group.selectionCount)/9")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func groupTokenIcons(for group: ScreenTimeGroup) -> some View {
        if group.selectionCount == 0 {
            Text("lock.noItems")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(
                        group.selection.applicationTokens.sorted(by: tokenSort),
                        id: \.self
                    ) { token in
                        tokenIcon(Label(token).labelStyle(.iconOnly))
                    }
                    ForEach(
                        group.selection.webDomainTokens.sorted(by: tokenSort),
                        id: \.self
                    ) { token in
                        tokenIcon(Label(token).labelStyle(.iconOnly))
                    }
                }
            }
            .contentMargins(.leading, 12)
        }
    }

    /// GroupCardView와 동일한 OS 분기 방식(FamilyControls Label 크기 함정은 Presentation
    /// CLAUDE.md 주의사항 참고). LockOptions는 작은 요약 미리보기라 크기만 작게(20) 둔다:
    /// iOS 26+는 기본 아이콘이 작아 scaleEffect로 키워 칸에 맞추고, iOS 26 미만은 기본이 커서
    /// 키우면 잘리므로 쌩 라벨에 간격만 준다.
    @ViewBuilder
    private func tokenIcon(_ label: some View) -> some View {
        if #available(iOS 26.0, *) {
            label
                .scaleEffect(0.95)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            label
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(.trailing, 4)
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
        .accessibilityElement(children: .combine)
    }
}
