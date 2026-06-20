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

    @State private var isShowingEditConfirm = false
    @State private var isShowingLimitConfirm = false
    @State private var isShowingDeleteConfirm = false
    @State private var isShowingDeleteRegularConfirm = false

    private var isLocked: Bool {
        viewModel.lockedGroupIDs.contains(group.id)
    }

    private var isOverrideActive: Bool {
        viewModel.overrideGroupIDs.contains(group.id)
    }

    /// 적용(commit)된 그룹은 우회 방지를 위해 편집/한도/삭제 전에 광고 게이트를 거친다.
    /// draft(미적용) 그룹은 광고 없이 자유롭게 수정·삭제할 수 있다.
    private var isEditRestricted: Bool {
        group.isApplied
    }

    /// draft 그룹은 규칙 선택 + 제한 항목이 모두 갖춰져야 적용할 수 있다.
    private var canApply: Bool {
        group.ruleKind != nil && group.selectionCount > 0
    }

    /// 적용 버튼이 비활성일 때 무엇이 부족한지 안내하는 캡션.
    private var applyHintCaption: String? {
        guard !group.isApplied, !canApply else { return nil }
        if group.ruleKind == nil && group.selectionCount == 0 {
            return String(localized: "group.apply.hint.both")
        }
        if group.ruleKind == nil {
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

                    GroupStatusBadge(
                        title: viewModel.statusTitle(for: group),
                        tint: viewModel.statusTint(for: group)
                    )
                }

                Spacer()

                Button(role: .destructive) {
                    if isEditRestricted {
                        isShowingDeleteConfirm = true
                    } else {
                        isShowingDeleteRegularConfirm = true
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
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

            Button {
                if isEditRestricted { isShowingLimitConfirm = true } else { onPresentRuleEditor(group) }
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 18)
                        .padding(.vertical, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .confirmationDialog(restrictedDialogTitle, isPresented: $isShowingLimitConfirm) {
                Button("group.ad.change") {
                    onPresentRuleEditor(group)
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text(restrictedDialogMessage)
            }
            .padding(.bottom, 14)

            if isLocked {
                Button {
                    onUnlockGroup(group.id)
                } label: {
                    Label("group.unlock", systemImage: "lock.open")
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

    @ViewBuilder
    private var editTokenList: some View {
        if group.selectionCount == 0 {
            Button {
                if isEditRestricted { isShowingEditConfirm = true } else { onPresentPicker(group) }
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
                if isEditRestricted { isShowingEditConfirm = true } else { onPresentPicker(group) }
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
                        Image(systemName: "square.grid.2x2")
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
