//
//  StrictLockSheet.swift
//  GoldTime
//
//  연장 불가 모드(기간 강력 잠금) 켜기·연장 시트. 단일 sheet 안에서 콘텐츠 단계를
//  전환한다(설정 → 최종 확인). 시트 안에서 confirmationDialog → modal 연쇄는 타이밍
//  글리치가 남아 쓰지 않는다(Presentation/CLAUDE.md "presentation 전환 타이밍" 참조) —
//  강한 확인 2단계는 같은 시트의 @State 콘텐츠 전환으로만 구현한다.
//
//  두 진입 모드가 있다:
//  - 적용 전 그룹(켜기): 기간 선택 + 고지 목록 + 최종 확인.
//  - 연장 불가 기간 중인 그룹(현황/연장): 현재 상태 + "지금보다 길게만" 연장(만료가 늘어나는 프리셋만 활성).
//

import SwiftUI

struct StrictLockSheet: View {
    let group: ScreenTimeGroup
    let now: Date
    let onConfirm: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var stage: Stage
    @State private var selectedDays: Int

    /// 시트 안 콘텐츠 단계. 프리뷰가 최종 확인 화면을 바로 열 수 있게 internal로 둔다.
    enum Stage { case config, confirm }

    private let presets = ManageGroupsUseCase.strictLockDayPresets

    /// `initialStage`·`initialDays`는 프리뷰가 특정 화면·선택 상태를 바로 열기 위한 값이다
    /// (기본값은 프로덕션 동작 그대로: 설정 단계 + 아래 규칙으로 계산한 기본 기간).
    init(
        group: ScreenTimeGroup,
        now: Date = Date(),
        initialStage: Stage = .config,
        initialDays: Int? = nil,
        onConfirm: @escaping (Int) -> Void
    ) {
        self.group = group
        self.now = now
        self.onConfirm = onConfirm
        _stage = State(initialValue: initialStage)
        if let initialDays {
            _selectedDays = State(initialValue: initialDays)
            return
        }
        // 기본 선택은 기본 기간(1일 — 첫 프리셋이라 칩이 선택되고 휠은 접힌 채로 열린다).
        // 연장 진입에서 이미 그보다 길게 잠겨 있으면 만료가 실제로 늘어나는 가장 짧은 기간으로
        // 폴백한다(프리셋 → 커스텀 범위 순).
        let presets = ManageGroupsUseCase.strictLockDayPresets
        let defaultDays = ManageGroupsUseCase.strictLockDefaultDays
        if Self.isDayEnabled(defaultDays, group: group, now: now) {
            _selectedDays = State(initialValue: defaultDays)
            return
        }
        let enabledPreset = presets.first { Self.isDayEnabled($0, group: group, now: now) }
        let enabledCustom = ManageGroupsUseCase.strictLockDayRange
            .first { Self.isDayEnabled($0, group: group, now: now) }
        _selectedDays = State(initialValue: enabledPreset ?? enabledCustom ?? presets.first ?? 1)
    }

    private var isActive: Bool { group.isStrictLockActive(at: now) }

    /// 남은 일수(마지막 날 = 1). 연장 불가 기간 중이 아니면 nil.
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

    /// 연장 가능한 기간이 하나라도 있는지(커스텀 상한까지 전부 만료 축소면 이미 최대).
    private var canExtend: Bool {
        ManageGroupsUseCase.strictLockDayRange.contains { isDayEnabled($0) }
    }

    /// 커스텀 칩이 선택된 상태(프리셋 칩에 없는 기간을 고른 것 — 기본값 1일은 프리셋이라 해당 없음).
    private var isCustomSelected: Bool { !presets.contains(selectedDays) }

    /// 커스텀 휠에서 고를 수 있는 기간. 연장이면 만료가 실제로 늘어나는 값만 남긴다.
    private var selectableCustomDays: [Int] {
        ManageGroupsUseCase.strictLockDayRange.filter { isDayEnabled($0) }
    }

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

    // MARK: - 켜기(적용 전)

    private var turnOnConfigStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                periodSection
                expiryPreview.font(.subheadline.weight(.semibold))
                disclosureList
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
            if isCustomSelected {
                customDaysWheel
            }
        }
    }

    /// 기간 선택 칩(1·3·7일 + 커스텀). 연장 모드에서 만료가 늘지 않는 값은 disabled 처리한다.
    private var presetChips: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.self) { day in
                chip(title: Text("strict.sheet.day \(day)"), selected: selectedDays == day, enabled: isDayEnabled(day)) {
                    selectedDays = day
                }
            }
            // 커스텀: 선택된 값이 프리셋에 없으면 칩에 그 값을 그대로 보여준다(예: "10일").
            chip(
                title: isCustomSelected ? Text("strict.sheet.day \(selectedDays)") : Text("strict.sheet.day.custom"),
                selected: isCustomSelected,
                enabled: !selectableCustomDays.isEmpty
            ) {
                // 커스텀으로 전환할 때는 시드 기간(10일)을 우선 잡고, 연장이라 그게 이미 짧으면
                // 고를 수 있는 가장 작은 비프리셋 기간부터 시작한다.
                selectedDays = selectableCustomDays.first(where: { $0 == ManageGroupsUseCase.strictLockCustomSeedDays })
                    ?? selectableCustomDays.first(where: { !presets.contains($0) })
                    ?? selectableCustomDays.first
                    ?? selectedDays
            }
        }
    }

    private func chip(
        title: Text,
        selected: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            title
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? Color.accent : Color(.tertiarySystemGroupedBackground))
                .foregroundStyle(selected ? .black : (enabled ? .primary : .secondary))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    /// 커스텀 휠(최대 30일). 상한은 실수 보호 — 한 번 걸면 못 푸는 모드라 무한정 긴 기간은 사고다.
    @ViewBuilder
    private var customDaysWheel: some View {
        if !selectableCustomDays.isEmpty {
            Picker("strict.sheet.period", selection: $selectedDays) {
                ForEach(selectableCustomDays, id: \.self) { day in
                    Text("strict.sheet.day \(day)").tag(day)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 120)
            .clipped()
        }
    }

    @ViewBuilder
    private var expiryPreview: some View {
        if let expiry = Self.expiry(days: selectedDays, now: now) {
            Label(
                String(localized: "strict.sheet.expiry \(goldTimeStrictLockedUntilText(expiry))"),
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
            noticeRow("hourglass", "strict.notice.extendLocked")
            noticeRow("pencil.slash", "strict.notice.editLocked")
            noticeRow("lock.fill", "strict.notice.noRelease")
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

    // MARK: - 현황/연장(연장 불가 기간 중)

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
                infoRow("play.circle", String(localized: "strict.active.startedAt \(goldTimeShortDateText(started))"))
            }
            if let until = group.strictUntil {
                infoRow("calendar", String(localized: "strict.active.expiresAt \(goldTimeStrictLockedUntilText(until))"))
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
                if isCustomSelected {
                    customDaysWheel
                }
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
                    Text("strict.confirm.body \(selectedDays) \(goldTimeStrictLockedUntilText(expiry))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
            VStack(spacing: 12) {
                // 파괴가 아니라 설정이므로 빨강이 아니라 accent.
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
        // 배경(.bar 등)을 두지 않아 하단 버튼 영역이 시트 배경과 같은 색으로 자연스럽게 이어진다
        // (StrictLockBetaSheet의 확인 버튼과 동일한 처리).
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

#if DEBUG
private func makePreviewGroup(strictUntil: Date? = nil, startedAt: Date? = nil) -> ScreenTimeGroup {
    ScreenTimeGroup(
        name: "SNS",
        dailyLimitMinutes: 30,
        ruleKind: .dailyLimit,
        isApplied: true,
        strictUntil: strictUntil,
        strictStartedAt: startedAt
    )
}

#Preview("켜기 — 기간 선택") {
    StrictLockSheet(group: makePreviewGroup()) { _ in }
}

#Preview("진행 중 — 현황·연장") {
    let now = Date()
    let until = Calendar.current.date(byAdding: .day, value: 5, to: Calendar.current.startOfDay(for: now))
    let started = Calendar.current.date(byAdding: .day, value: -2, to: now)
    return StrictLockSheet(group: makePreviewGroup(strictUntil: until, startedAt: started)) { _ in }
}

// 기본값(1일)은 프리셋 칩이라 휠이 접힌 채 열린다 — 휠 상태는 이 프리뷰로만 본다.
#Preview("켜기 — 커스텀(휠)") {
    StrictLockSheet(group: makePreviewGroup(), initialDays: 12) { _ in }
}

#Preview("최종 확인") {
    StrictLockSheet(group: makePreviewGroup(), initialStage: .confirm) { _ in }
}

// 언어 variant — Canvas에서 en/ja 잘림 확인용. 다크·큰 글자는 Canvas의 Variants 버튼으로 토글한다.
// LocalizedStringKey 문구(고지·본문·부제)는 아래 locale을 따르지만, 코드의 String(localized:)
// (만료일·남은 일수)는 스킴 App Language로만 바뀐다 — 잘림 위험이 큰 문구는 전부 전자라 여기서 잡힌다.
#Preview("켜기 — EN") {
    StrictLockSheet(group: makePreviewGroup()) { _ in }
        .environment(\.locale, .init(identifier: "en"))
}

#Preview("켜기 — JA") {
    StrictLockSheet(group: makePreviewGroup()) { _ in }
        .environment(\.locale, .init(identifier: "ja"))
}

#Preview("최종 확인 — EN") {
    StrictLockSheet(group: makePreviewGroup(), initialStage: .confirm) { _ in }
        .environment(\.locale, .init(identifier: "en"))
}

#Preview("최종 확인 — JA") {
    StrictLockSheet(group: makePreviewGroup(), initialStage: .confirm) { _ in }
        .environment(\.locale, .init(identifier: "ja"))
}
#endif
