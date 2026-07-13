//
//  StrictLockSheet.swift
//  GoldTime
//
//  금고 모드(기간 약정 강력 잠금) 켜기·연장 시트. 단일 sheet 안에서 콘텐츠 단계를
//  전환한다(설정 → 최종 확인). 시트 안에서 confirmationDialog → modal 연쇄는 타이밍
//  글리치가 남아 쓰지 않는다(Presentation/CLAUDE.md "presentation 전환 타이밍" 참조) —
//  강한 확인 2단계는 같은 시트의 @State 콘텐츠 전환으로만 구현한다.
//
//  두 진입 모드가 있다:
//  - 비약정 그룹(켜기): 기간 선택 + 고지 목록 + 최종 확인.
//  - 약정 중 그룹(현황/연장): 약정 정보 + "지금보다 길게만" 연장(만료가 늘어나는 프리셋만 활성).
//

import SwiftUI

struct StrictLockSheet: View {
    let group: ScreenTimeGroup
    let now: Date
    let onConfirm: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var stage: Stage = .config
    @State private var selectedDays: Int

    private enum Stage { case config, confirm }

    private let presets = ManageGroupsUseCase.strictLockDayPresets

    init(group: ScreenTimeGroup, now: Date = Date(), onConfirm: @escaping (Int) -> Void) {
        self.group = group
        self.now = now
        self.onConfirm = onConfirm
        // 기본 선택: 켜기면 첫 프리셋, 연장이면 만료가 늘어나는 첫 프리셋.
        let presets = ManageGroupsUseCase.strictLockDayPresets
        let firstEnabled = presets.first { Self.isDayEnabled($0, group: group, now: now) }
        _selectedDays = State(initialValue: firstEnabled ?? presets.first ?? 1)
    }

    private var isActive: Bool { group.isStrictLockActive(at: now) }

    /// 남은 일수(마지막 날 = 1). 약정 중이 아니면 nil.
    private var remainingDays: Int? {
        guard isActive, let until = group.strictUntil else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: until).day
    }

    private static func expiry(days: Int, now: Date) -> Date? {
        ScreenTimeGroup.strictLockExpiry(days: days, from: now)
    }

    /// 이 프리셋을 지금 적용하면 실제로 잠기는지(연장은 만료가 늘어나는 방향만 유효).
    private static func isDayEnabled(_ day: Int, group: ScreenTimeGroup, now: Date) -> Bool {
        guard let expiry = expiry(days: day, now: now) else { return false }
        if group.isStrictLockActive(at: now), let until = group.strictUntil {
            return expiry > until
        }
        return true
    }

    private func isDayEnabled(_ day: Int) -> Bool {
        Self.isDayEnabled(day, group: group, now: now)
    }

    /// 연장 가능한 프리셋이 하나라도 있는지(전부 만료 축소면 이미 최대).
    private var canExtend: Bool { presets.contains { isDayEnabled($0) } }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(isActive ? "strict.active.title" : "strict.sheet.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if stage == .config {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("common.cancel") { dismiss() }
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .config:
            if isActive { activeConfigStage } else { turnOnConfigStage }
        case .confirm:
            confirmStage
        }
    }

    // MARK: - 켜기(비약정)

    private var turnOnConfigStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                periodSection
                expiryPreview.font(.subheadline.weight(.semibold))
                disclosureList
                targetSection
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            primaryButton(title: "strict.sheet.commit") { stage = .confirm }
        }
    }

    private var periodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("strict.sheet.period")
                .font(.subheadline.weight(.semibold))
            presetChips
        }
    }

    /// 기간 선택 칩. 연장 모드에서 만료가 늘지 않는 프리셋은 disabled 처리한다.
    private var presetChips: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.self) { day in
                let enabled = isDayEnabled(day)
                Button {
                    selectedDays = day
                } label: {
                    Text("strict.sheet.day \(day)")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedDays == day ? Color.accent : Color(.tertiarySystemGroupedBackground))
                        .foregroundStyle(selectedDays == day ? .black : (enabled ? .primary : .secondary))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.4)
            }
        }
    }

    @ViewBuilder
    private var expiryPreview: some View {
        if let expiry = Self.expiry(days: selectedDays, now: now) {
            Label(
                String(localized: "strict.sheet.expiry \(goldTimeStrictExpiryDateText(expiry))"),
                systemImage: "calendar"
            )
            .foregroundStyle(Color.accent)
        }
    }

    /// 고지 5행. 주 문장은 **사용자가 겪는 결과**만 말하고, 그렇게 되는 수단·부작용(기기 전체 앱
    /// 삭제가 함께 막힘 / 날짜·시간이 자동 고정됨)은 각주로 내린다 — 수단을 앞세우면 "왜 날짜를
    /// 건드리지?" 같은 의심이 먼저 온다.
    private var disclosureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("strict.sheet.intro")
                .font(.headline)
            noticeRow("lock.fill", "strict.notice.noRelease")
            noticeRow("pencil.slash", "strict.notice.editLocked")
            noticeRow("hourglass", "strict.notice.extendLocked")
            noticeRow("trash.slash", "strict.notice.appRemoval", footnote: "strict.notice.appRemoval.footnote")
            noticeRow("clock.badge.xmark", "strict.notice.autoDateTime", footnote: "strict.notice.autoDateTime.footnote")
        }
    }

    private func noticeRow(
        _ icon: String,
        _ text: LocalizedStringKey,
        footnote: LocalizedStringKey? = nil
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if let footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Color.accent)
        }
    }

    /// 잠글 그룹 재확인(이름 + 항목 개수). 토큰 아이콘 나열은 과해서 텍스트로만 요약한다.
    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("strict.sheet.target")
                .font(.subheadline.weight(.semibold))
            HStack {
                Text(group.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text("strict.sheet.itemCount \(group.selectionCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 현황/연장(약정 중)

    private var activeConfigStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                activeInfoSection
                extendSection
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            primaryButton(title: "strict.active.extend.button", enabled: canExtend) { stage = .confirm }
        }
    }

    private var activeInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let days = remainingDays {
                Label(String(localized: "strict.active.remaining \(days)"), systemImage: "lock.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.accent)
            }
            if let started = group.strictStartedAt {
                infoRow("play.circle", String(localized: "strict.active.startedAt \(goldTimeStrictExpiryDateText(started))"))
            }
            if let until = group.strictUntil {
                infoRow("calendar", String(localized: "strict.active.expiresAt \(goldTimeStrictExpiryDateText(until))"))
            }
            infoRow("lock.fill", String(localized: "strict.active.noRelease"))
        }
    }

    private func infoRow(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
        }
    }

    private var extendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("strict.active.extend")
                .font(.subheadline.weight(.semibold))
            Text("strict.active.extend.hint")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if canExtend {
                presetChips
                expiryPreview.font(.footnote.weight(.semibold))
            } else {
                Text("strict.active.extend.none")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 최종 확인(공용)

    private var confirmStage: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accent)
                Text("strict.confirm.title")
                    .font(.title2.bold())
                if let expiry = Self.expiry(days: selectedDays, now: now) {
                    Text("strict.confirm.body \(selectedDays) \(goldTimeStrictExpiryDateText(expiry))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
            VStack(spacing: 12) {
                // 파괴가 아니라 약정이므로 빨강이 아니라 accent.
                Button {
                    onConfirm(selectedDays)
                } label: {
                    Text("strict.confirm.button")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GoldTimeButtonStyle(background: Color.accent, foreground: .black))
                Button("strict.confirm.back") { stage = .config }
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private func primaryButton(
        title: LocalizedStringKey,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GoldTimeButtonStyle(background: Color.accent, foreground: .black))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
