//
//  GroupCardView.swift
//  GoldTime
//

import FamilyControls
import SwiftUI

struct GroupCardView: View {
    let group: ScreenTimeGroup
    let viewModel: HomeViewModel
    let onDeleteGroup: (UUID) -> Void
    let onUpdateGroupName: (UUID, String) -> Void
    let onPresentPicker: (ScreenTimeGroup) -> Void
    let onPresentRuleEditor: (ScreenTimeGroup) -> Void
    let onUnlockGroup: (UUID) -> Void
    let onApplyGroup: (UUID) -> Void
    let onPresentStrictLock: (ScreenTimeGroup) -> Void
    /// 연장 불가 모드 기능 토글(설정, 기본 Off). Off면 연장 불가 행 자체를 그리지 않는다.
    let isStrictLockFeatureEnabled: Bool

    @State private var isShowingEditConfirm = false
    @State private var isShowingDeleteConfirm = false
    @State private var isShowingDeleteRegularConfirm = false

    private var isLocked: Bool {
        viewModel.lockedGroupIDs.contains(group.id)
    }

    private var isOverrideActive: Bool {
        viewModel.overrideGroupIDs.contains(group.id)
    }

    /// 연장 불가 기간 중인지. 규칙 행·연장 불가 행의 자물쇠 신호와 삭제 버튼 비활성에 쓴다.
    private var isStrictActive: Bool {
        viewModel.isStrictLocked(group)
    }

    /// 적용(commit)된 그룹은 우회 방지를 위해 앱 선택 편집·삭제는 진입 전에 광고 게이트를 거친다.
    /// 규칙 변경은 진입은 무료고 완료(변경이 있을 때만) 시점에 게이트를 건다(ContentViewModel).
    /// draft(미적용) 그룹은 광고 없이 자유롭게 수정·삭제할 수 있다.
    private var isEditRestricted: Bool {
        group.isApplied
    }

    /// 규칙(단일 또는 요일별)이 정해졌는지. 둘 다 없으면 draft(설정 필요).
    private var hasRule: Bool {
        group.ruleKind != nil || group.usesWeekdayRules
    }

    /// draft 그룹은 규칙 선택 + 제한 항목이 모두 갖춰져야 적용할 수 있다.
    private var canApply: Bool {
        hasRule && group.selectionCount > 0
    }

    /// 적용 버튼이 비활성일 때 무엇이 부족한지 안내하는 캡션.
    private var applyHintCaption: String? {
        guard !group.isApplied, !canApply else { return nil }
        if !hasRule && group.selectionCount == 0 {
            return String(localized: "group.apply.hint.both")
        }
        if !hasRule {
            return String(localized: "group.apply.hint.rule")
        }
        return String(localized: "group.apply.hint.selection")
    }

    private let restrictedDialogTitle: LocalizedStringKey = "group.restricted.title"

    private var restrictedDialogMessage: String {
        String(localized: "group.restricted.message")
    }

    private var selectionCountText: String {
        "\(group.selectionCount)/\(viewModel.maxAppsPerGroup)"
    }

    /// FamilyControls Label 아이콘 크기는 제어 불가하고 기본 크기가 OS마다 다르다(Presentation
    /// CLAUDE.md 주의사항 참고). OS별로 라벨 체인을 통째로 다르게 적용한다.
    @ViewBuilder
    private func tokenIcon(_ label: some View) -> some View {
        if #available(iOS 26.0, *) {
            // iOS 26+: 기본 아이콘이 작아 scaleEffect로 키워 칸에 맞춘다.
            label
                .scaleEffect(1.3)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(.trailing, 6)
        } else {
            // iOS 26 미만: 기본 아이콘이 커서 키우면 잘리므로 쌩 라벨에 간격만 준다.
            label
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(.trailing, 8)
        }
    }

    /// 앱 토큰 묶음과 웹 토큰 묶음 사이 간격. 기본 아이콘 크기가 OS마다 달라 버전별로 조절한다.
    private var tokenGroupSpacing: CGFloat {
        if #available(iOS 26.0, *) { return 0 }
        return 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                IconTile(
                    systemName: viewModel.statusIcon(for: group),
                    tint: viewModel.statusTint(for: group)
                )
                .padding(.trailing, 12)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("group.name.placeholder", text: Binding(
                        get: { group.name },
                        set: { onUpdateGroupName(group.id, $0) }
                    ))
                    .font(.headline)

                    HStack(spacing: 6) {
                        GroupStatusBadge(
                            title: viewModel.statusTitle(for: group),
                            tint: viewModel.statusTint(for: group)
                        )
                        if let strictText = viewModel.strictBadgeText(for: group) {
                            strictBadge(strictText)
                        }
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    // 연장 불가 기간 중엔 광고 게이트 다이얼로그를 띄우지 않고 곧장 ContentViewModel로
                    // 보낸다 — 거기 strict guard가 "연장 불가 기간이 끝나야 지울 수 있어요" alert을 띄운다.
                    // (버튼을 disabled로 두면 왜 안 되는지 설명할 자리가 없어 dim만 남긴다.)
                    if isStrictActive {
                        onDeleteGroup(group.id)
                    } else if isEditRestricted {
                        isShowingDeleteConfirm = true
                    } else {
                        isShowingDeleteRegularConfirm = true
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .opacity(isStrictActive ? 0.45 : 1)
                .confirmationDialog("group.delete.title", isPresented: $isShowingDeleteRegularConfirm) {
                    Button("common.delete", role: .destructive) {
                        onDeleteGroup(group.id)
                    }
                    Button("common.cancel", role: .cancel) {}
                } message: {
                    Text("group.delete.message")
                }
                .confirmationDialog(restrictedDialogTitle, isPresented: $isShowingDeleteConfirm) {
                    Button("group.ad.delete", role: .destructive) {
                        onDeleteGroup(group.id)
                    }
                    Button("common.cancel", role: .cancel) {}
                } message: {
                    Text(restrictedDialogMessage)
                }
            }
            .padding(.bottom, 14)

            // 진행바는 카드 이미지(상단 행) 아래 전용 줄에 둔다.
            // "남은 한도" 라벨이 바를 잘라먹지 않도록 바를 한 줄에서 전체 길이로 표시.
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                if let progress = viewModel.overrideProgress(for: group) {
                    HStack(spacing: 8) {
                        Text("home.remainingLimit")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        SegmentedProgressBar(
                            remaining: progress.remaining,
                            total: progress.total,
                            tint: .blue,
                            accessibilityText: progress.accessibilityLabel
                        )
                    }
                    .padding(.bottom, 14)
                } else if let progress = viewModel.lockProgress(for: group) {
                    HStack(spacing: 8) {
                        Text("home.remainingLimit")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        SegmentedProgressBar(
                            remaining: progress.remaining,
                            total: progress.total,
                            tint: .green,
                            accessibilityText: progress.accessibilityLabel
                        )
                    }
                    .padding(.bottom, 14)
                }
            }

            Divider()
                .padding(.bottom, 14)

            // 규칙 편집기 진입은 무료(보기만 하는 진입에는 게이트 없음). 적용된 그룹의 광고
            // 게이트는 완료 시점에 변경이 있을 때만 뜬다(ContentViewModel.requiresAdForRuleCommit).
            Button {
                onPresentRuleEditor(group)
            } label: {
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.ruleRowTitle(for: group))
                            .font(.subheadline.weight(.semibold))
                        Text(viewModel.ruleRowSubtitle(for: group))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // 연장 불가 기간 중이면 편집 진입이 막히는 시각 신호로 chevron 대신 자물쇠(탭은 그대로 가능).
                    Image(systemName: isStrictActive ? "lock.fill" : "chevron.right")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 18)
                        .padding(.vertical, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)

            if isStrictLockFeatureEnabled && group.isApplied {
                Divider()
                    .padding(.bottom, 14)
                strictRow
                    .padding(.bottom, 14)
            }

            if isLocked {
                Button {
                    onUnlockGroup(group.id)
                } label: {
                    Label("group.useMore", systemImage: "hourglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GoldTimeButtonStyle(background: Color.red.opacity(0.12), foreground: .red))
                .padding(.bottom, 14)
            }

            editTokenList
                .confirmationDialog(restrictedDialogTitle, isPresented: $isShowingEditConfirm) {
                    Button("group.ad.edit") {
                        onPresentPicker(group)
                    }
                    Button("common.cancel", role: .cancel) {}
                } message: {
                    Text(restrictedDialogMessage)
                }
                .padding(.bottom, 14)

            if !group.isApplied {
                applySection
                    .padding(.bottom, 14)
            }
        }
        .cardContainer()
    }

    /// 연장 불가 행(규칙 행 바로 아래). 규칙 행과 같은 시각 언어(제목+부제+trailing)이자 같은 문법 —
    /// **제목이 적용 전엔 할 일("연장 불가 모드 설정"), 적용 중엔 현재 상태("연장 불가 중")** 로 바뀐다
    /// (규칙 행의 "차단 규칙 선택" → "일일 한도"와 동일). 부제는 적용 중이면 만료일, trailing은 자물쇠.
    private var strictRow: some View {
        Button {
            onPresentStrictLock(group)
        } label: {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isStrictActive ? "group.strictRow.title.active" : "group.strictRow.title.inactive")
                        .font(.subheadline.weight(.semibold))
                    strictRowSubtitle
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isStrictActive ? "lock.fill" : "chevron.right")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
                    .padding(.vertical, 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var strictRowSubtitle: Text {
        if isStrictActive, let until = group.strictUntil {
            return Text("group.strictRow.subtitle.active \(goldTimeStrictLockedUntilText(until))")
        }
        return Text("group.strictRow.subtitle.inactive")
    }

    /// 연장 불가 배지("🔒 N일 남음"). `Label`은 아이콘–텍스트 간격을 제어할 수 없어 자물쇠 오른쪽에
    /// 큰 여백이 남는다 — HStack으로 직접 조립한다.
    private func strictBadge(_ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill")
            Text(text)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Color.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.accent.opacity(0.15))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var applySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onApplyGroup(group.id)
            } label: {
                Label("group.apply", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GoldTimeButtonStyle(background: Color.accent, foreground: .black))
            .disabled(!canApply)
            .opacity(canApply ? 1 : 0.45)

            if let applyHintCaption {
                Text(applyHintCaption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if canApply {
                Text("group.apply.hint.applied")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 항목(앱 선택) 편집 탭. **연장 불가 기간 중이면 광고 게이트 다이얼로그를 띄우지 않고** 곧장
    /// ContentViewModel로 보낸다 — 거기 strict guard가 차단 안내 alert만 띄운다. 다이얼로그를
    /// 먼저 띄우면 "광고 보고 편집하기"라는 연장 불가 모드와 모순되는 안내가 뜨고, 확인 시 다이얼로그가
    /// 닫히는 같은 사이클에 alert를 세팅하게 돼 SwiftUI가 표시를 건너뛴다(Presentation/CLAUDE.md).
    private func tapEditSelection() {
        if isStrictActive || !isEditRestricted {
            onPresentPicker(group)
            return
        }
        isShowingEditConfirm = true
    }

    @ViewBuilder
    private var editTokenList: some View {
        if group.selectionCount == 0 {
            Button {
                tapEditSelection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                    Text("group.selectItems")
                    Text(selectionCountText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GoldTimeButtonStyle(background: Color(.tertiarySystemGroupedBackground), foreground: .primary))
        } else {
            Button {
                tapEditSelection()
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            Text("group.items")
                                .font(.subheadline.weight(.semibold))
                            Text(selectionCountText)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        Spacer()
                        // 연장 불가 기간 중이면 항목 편집도 막히므로 규칙 행과 같은 자물쇠 신호를 준다
                        // (탭은 가능 — ContentViewModel이 만료일 안내 alert을 띄운다).
                        Image(systemName: isStrictActive ? "lock.fill" : "square.grid.2x2")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(
                                group.selection.applicationTokens.sorted {
                                    ((try? JSONEncoder().encode($0)) ?? Data())
                                        .lexicographicallyPrecedes((try? JSONEncoder().encode($1)) ?? Data())
                                },
                                id: \.self
                            ) { token in
                                tokenIcon(Label(token).labelStyle(.iconOnly))
                            }
                            Spacer()
                                .frame(width: tokenGroupSpacing)
                            ForEach(
                                group.selection.webDomainTokens.sorted {
                                    ((try? JSONEncoder().encode($0)) ?? Data())
                                        .lexicographicallyPrecedes((try? JSONEncoder().encode($1)) ?? Data())
                                },
                                id: \.self
                            ) { token in
                                tokenIcon(Label(token).labelStyle(.iconOnly))
                            }
                        }
                    }
                    .contentMargins(.leading, 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

#if DEBUG
private func makeCardPreview(strictUntil: Date?) -> some View {
    let group = ScreenTimeGroup(
        name: "SNS",
        dailyLimitMinutes: 30,
        ruleKind: .dailyLimit,
        isApplied: true,
        strictUntil: strictUntil
    )
    let viewModel = HomeViewModel(
        groups: [group],
        todayStats: DailyStats(dateKey: "2026-07-13"),
        isMonitoring: true,
        isShieldActive: false,
        shieldOverrideUntil: nil,
        successMessage: nil,
        errorMessage: nil
    )
    return ScrollView {
        GroupCardView(
            group: group,
            viewModel: viewModel,
            onDeleteGroup: { _ in },
            onUpdateGroupName: { _, _ in },
            onPresentPicker: { _ in },
            onPresentRuleEditor: { _ in },
            onUnlockGroup: { _ in },
            onApplyGroup: { _ in },
            onPresentStrictLock: { _ in },
            isStrictLockFeatureEnabled: true
        )
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("카드 — 연장 불가 진행 중") {
    let until = Calendar.current.date(byAdding: .day, value: 5, to: Calendar.current.startOfDay(for: Date()))
    return makeCardPreview(strictUntil: until)
}

#Preview("카드 — 대기(연장 불가 행)") {
    makeCardPreview(strictUntil: nil)
}

// 언어 variant — en/ja 잘림 확인용(다크·큰 글자는 Canvas Variants 버튼). 배지·만료일은
// String(localized:)라 locale을 안 따르지만 "5일 남음"처럼 짧아 잘림 위험이 없다. 반면 행 제목
// ("연장 불가 모드 설정")은 LocalizedStringKey라 여기서 en/ja 폭을 확인한다.
#Preview("카드 연장불가행 — EN") {
    makeCardPreview(strictUntil: nil)
        .environment(\.locale, .init(identifier: "en"))
}

#Preview("카드 연장불가행 — JA") {
    makeCardPreview(strictUntil: nil)
        .environment(\.locale, .init(identifier: "ja"))
}

#Preview("카드 진행중 — EN") {
    let until = Calendar.current.date(byAdding: .day, value: 5, to: Calendar.current.startOfDay(for: Date()))
    return makeCardPreview(strictUntil: until)
        .environment(\.locale, .init(identifier: "en"))
}
#endif
