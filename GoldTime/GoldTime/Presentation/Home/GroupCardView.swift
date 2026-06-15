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
            return "규칙과 제한 항목을 먼저 정해 주세요."
        }
        if group.ruleKind == nil {
            return "차단 규칙을 먼저 골라 주세요."
        }
        return "제한 항목을 하나 이상 담아 주세요."
    }

    private let restrictedDialogTitle = "적용된 그룹"

    private var restrictedDialogMessage: String {
        "적용된 그룹은 광고를 본 뒤 편집하거나 삭제할 수 있어요."
    }

    private var selectionCountText: String {
        "\(group.selectionCount)/\(viewModel.maxAppsPerGroup)"
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
                    TextField("그룹명", text: Binding(
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
                .confirmationDialog("그룹 삭제", isPresented: $isShowingDeleteRegularConfirm) {
                    Button("삭제", role: .destructive) {
                        onDeleteGroup(group.id)
                    }
                    Button("취소", role: .cancel) {}
                } message: {
                    Text("그룹을 삭제하면 되돌릴 수 없어요.")
                }
                .confirmationDialog(restrictedDialogTitle, isPresented: $isShowingDeleteConfirm) {
                    Button("광고 보고 삭제하기", role: .destructive) {
                        onDeleteGroup(group.id)
                    }
                    Button("취소", role: .cancel) {}
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
                        Text("남은 한도")
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
                        Text("남은 한도")
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
                Button("광고 보고 변경하기") {
                    onPresentRuleEditor(group)
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text(restrictedDialogMessage)
            }
            .padding(.bottom, 14)

            if isLocked {
                Button {
                    onUnlockGroup(group.id)
                } label: {
                    Label("잠금 해제", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GoldTimeButtonStyle(background: Color.red.opacity(0.12), foreground: .red))
                .padding(.bottom, 14)
            }

            editTokenList
                .confirmationDialog(restrictedDialogTitle, isPresented: $isShowingEditConfirm) {
                    Button("광고 보고 편집하기") {
                        onPresentPicker(group)
                    }
                    Button("취소", role: .cancel) {}
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
                Label("적용하기", systemImage: "checkmark.shield")
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
                Text("적용하면 바로 차단 규칙이 시작되고, 적용 이후 수정 및 삭제에는 광고가 필요해요.")
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
                    Text("제한 항목 선택")
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
                            Text("제한 항목")
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
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(
                                group.selection.applicationTokens.sorted {
                                    ((try? JSONEncoder().encode($0)) ?? Data())
                                        .lexicographicallyPrecedes((try? JSONEncoder().encode($1)) ?? Data())
                                },
                                id: \.self
                            ) { token in
                                Label(token)
                                    .labelStyle(.iconOnly)
                                    .scaleEffect(1.3)
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            ForEach(
                                group.selection.webDomainTokens.sorted {
                                    ((try? JSONEncoder().encode($0)) ?? Data())
                                        .lexicographicallyPrecedes((try? JSONEncoder().encode($1)) ?? Data())
                                },
                                id: \.self
                            ) { token in
                                Label(token)
                                    .labelStyle(.iconOnly)
                                    .scaleEffect(1.3)
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .rowContainer()
        }
    }
}
