//
//  RuleEditorSheet.swift
//  GoldTime
//
//  그룹의 차단 규칙(일일 한도 / 시간대별 차단 / 쿨다운)을 고르고 편집하는 시트.
//  NavigationStack 2단계: 1단계 규칙 종류 선택 → 2단계 종류별 본문.
//  "요일별 규칙" 토글을 켜면 요일 묶음 리스트로 바뀌고, 묶음을 눌러 요일별 규칙을 편집한다.
//  묶음 리스트 상단의 주간 스트립(7칸)이 요일마다 규칙 종류를 아이콘으로 보여 주고,
//  칸을 탭하면 그 요일이 속한 묶음 편집으로 바로 들어간다.
//

import SwiftUI

struct RuleEditorSheet: View {
    @Binding var selectedKind: GroupRuleKind
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var timeWindows: [TimeWindow]
    @Binding var cooldownUsageMinutes: Int
    @Binding var cooldownDurationMinutes: Int
    /// 요일별 규칙(7개). nil이면 요일별 모드 OFF(기존 규칙 3종 리스트). non-nil이면 요일 묶음 리스트.
    @Binding var weekdayRules: [DayRule]?
    /// 설정의 주 시작 요일(1=일 … 7=토). 요일 표시 순서 계산에 쓴다.
    let weekStartDay: Int
    /// 그룹에 이미 커밋된 규칙. 아직 규칙을 고르지 않은(새) 그룹은 nil이라 체크표시가 없다.
    let currentKind: GroupRuleKind?
    /// 자정 근처(23:30+) 편집 안내. nil이면 미노출. 일일 한도·쿨다운 상세 본문에서만 띄운다
    /// (시간대별 차단은 모니터 영향이 없어 전달하지 않는다).
    let nearMidnightNotice: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    /// 요일 묶음 편집 push 스택. 묶음 행·"+ 추가"의 NavigationLink(value:)와 주간 스트립의
    /// 프로그램적 push(append)가 같은 스택을 공유한다.
    @State private var path: [BundleEditContext] = []

    /// 요일 표시 순서(설정의 주 시작 요일 기준). 0=일 … 6=토.
    private var orderedIndices: [Int] {
        WeekdayRulePolicy.displayOrderedIndices(weekStartDay: weekStartDay)
    }

    /// 요일별 규칙 전체 유효성. 위반 시 완료 버튼을 막고 사유를 노출한다.
    private var weekdayInvalidReason: WeekdayRulePolicy.InvalidReason? {
        guard let weekdayRules else { return nil }
        return WeekdayRulePolicy.firstInvalidReason(for: weekdayRules)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Toggle("rule.weekday.toggle", isOn: weekdayToggleBinding)
                } footer: {
                    Text("rule.weekday.toggle.footer")
                }

                if let weekdayRules {
                    weekdayBundleSection(weekdayRules)
                } else {
                    baseRuleSection
                }
            }
            // value 기반 push: 진입할 때마다 새 destination이 만들어져 @State가 항상 신선하다.
            // (inline destination 방식은 "+ 추가" 재진입 시 이전 선택이 잔존하는 함정이 있었다.)
            .navigationDestination(for: BundleEditContext.self) { context in
                WeekdayBundleEditView(
                    orderedIndices: orderedIndices,
                    initialDays: context.days,
                    initialRule: context.rule,
                    onSave: applyBundle
                )
            }
            .navigationTitle("rule.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel", action: onCancel)
                }
                // 요일별 모드는 루트에서 완료한다. 기존 3종은 각 상세 본문의 완료 버튼을 그대로 쓴다.
                if weekdayRules != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.done", action: onConfirm)
                            .fontWeight(.semibold)
                            .disabled(weekdayInvalidReason != nil)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - 요일 토글

    /// 토글 ON 시 현재 편집 중인 base 규칙(선택된 종류 + 파라미터)으로 7일을 시드하고,
    /// OFF 시 nil로 되돌려 기존 규칙 3종 리스트로 복귀한다.
    private var weekdayToggleBinding: Binding<Bool> {
        Binding(
            get: { weekdayRules != nil },
            set: { isOn in
                weekdayRules = isOn ? Array(repeating: currentBaseDayRule(), count: 7) : nil
            }
        )
    }

    private func currentBaseDayRule() -> DayRule {
        switch selectedKind {
        case .dailyLimit:
            return DayRule(kind: .dailyLimit, dailyLimitMinutes: hours * 60 + minutes)
        case .timeWindows:
            return DayRule(kind: .timeWindows, timeWindows: timeWindows)
        case .cooldown:
            return DayRule(
                kind: .cooldown,
                cooldownUsageMinutes: cooldownUsageMinutes,
                cooldownDurationMinutes: cooldownDurationMinutes
            )
        }
    }

    // MARK: - 기존 규칙 3종 리스트(요일별 OFF)

    @ViewBuilder
    private var baseRuleSection: some View {
        Section {
            ruleRow(
                kind: .dailyLimit,
                systemName: "timer",
                title: "rule.dailyLimit.title",
                subtitle: "rule.dailyLimit.subtitle"
            )
            ruleRow(
                kind: .timeWindows,
                systemName: "clock.badge.xmark",
                title: "rule.timeWindows.title",
                subtitle: "rule.timeWindows.subtitle"
            )
            ruleRow(
                kind: .cooldown,
                systemName: "cup.and.saucer.fill",
                title: "rule.cooldown.title",
                subtitle: "rule.cooldown.subtitle"
            )
        } footer: {
            Text("rule.footer")
        }
    }

    @ViewBuilder
    private func ruleRow(
        kind: GroupRuleKind,
        systemName: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey
    ) -> some View {
        NavigationLink {
            detail(for: kind)
        } label: {
            HStack(spacing: 14) {
                IconTile(systemName: systemName, tint: Color.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if currentKind == kind {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.accent)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func detail(for kind: GroupRuleKind) -> some View {
        switch kind {
        case .dailyLimit:
            DailyLimitDetailView(
                hours: $hours,
                minutes: $minutes,
                nearMidnightNotice: nearMidnightNotice,
                onConfirm: confirm(as: .dailyLimit)
            )
        case .timeWindows:
            TimeWindowsDetailView(
                windows: $timeWindows,
                onConfirm: confirm(as: .timeWindows)
            )
        case .cooldown:
            CooldownDetailView(
                usageMinutes: $cooldownUsageMinutes,
                durationMinutes: $cooldownDurationMinutes,
                nearMidnightNotice: nearMidnightNotice,
                onConfirm: confirm(as: .cooldown)
            )
        }
    }

    private func confirm(as kind: GroupRuleKind) -> () -> Void {
        {
            selectedKind = kind
            onConfirm()
        }
    }

    // MARK: - 요일 묶음 리스트(요일별 ON)

    @ViewBuilder
    private func weekdayBundleSection(_ rules: [DayRule]) -> some View {
        Section {
            if rules.count == 7 {
                WeekdayRuleStrip(
                    orderedIndices: orderedIndices,
                    rules: rules,
                    todayIndex: WeekdayRulePolicy.weekdayIndex(for: Date()),
                    onSelect: { index in
                        // path.isEmpty: NavigationLink와 달리 프로그램적 append는 debounce가
                        // 없어 연타 시 같은 화면이 중복 push되는 것을 막는다(스트립은 루트 전용).
                        guard path.isEmpty,
                              let bundle = Self.bundleContaining(day: index, in: rules) else { return }
                        path.append(BundleEditContext(days: bundle.days, rule: bundle.rule))
                    }
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }

            ForEach(bundles(from: rules)) { bundle in
                NavigationLink(value: BundleEditContext(days: bundle.days, rule: bundle.rule)) {
                    bundleRow(bundle)
                }
            }

            NavigationLink(value: BundleEditContext(days: [], rule: DayRule(kind: .dailyLimit, dailyLimitMinutes: 30))) {
                Label("rule.weekday.addBundle", systemImage: "plus")
            }
        } footer: {
            if let weekdayInvalidReason {
                Text(weekdayInvalidReason.userMessage)
                    .foregroundStyle(.red)
            } else {
                Text("rule.weekday.section.footer")
            }
        }
    }

    @ViewBuilder
    private func bundleRow(_ bundle: WeekdayBundle) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(daysLabel(for: bundle.days))
                .font(.body.weight(.semibold))
            Text(ruleSummary(for: bundle.rule))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func applyBundle(selected: Set<Int>, initial: Set<Int>, rule: DayRule) {
        guard let rules = weekdayRules else { return }
        weekdayRules = Self.applyingBundle(to: rules, selectedDays: selected, initialDays: initial, rule: rule)
    }

    /// 묶음 저장을 7요일 배열에 반영한 사본. 선택된 요일 → 이 규칙(다른 묶음에서 빼앗기),
    /// **이 묶음에서 해제된 요일 → 제한 없음**. 해제를 무동작으로 두면 토글 직후의 기본
    /// "월~일" 단일 묶음에서 주말을 빼는 첫 조작이 아무 변화가 없어 "반영이 안 된다"로 느껴진다
    /// ("요일을 빼면 그 요일은 규칙 없음"이라는 직관에 맞춘 동작 — 요일 섹션 footer로 안내).
    static func applyingBundle(
        to rules: [DayRule],
        selectedDays: Set<Int>,
        initialDays: Set<Int>,
        rule: DayRule
    ) -> [DayRule] {
        var result = rules
        for day in selectedDays where result.indices.contains(day) {
            result[day] = rule
        }
        for day in initialDays.subtracting(selectedDays) where result.indices.contains(day) {
            result[day] = DayRule(kind: .unrestricted)
        }
        return result
    }

    /// 스트립 칸의 규칙 아이콘. 규칙 3종은 기존 규칙 선택 행의 아이콘과 동일, 제한 없음은 대시.
    static func stripIconName(for kind: DayRuleKind) -> String {
        switch kind {
        case .unrestricted:
            return "minus"
        case .dailyLimit:
            return "timer"
        case .timeWindows:
            return "clock.badge.xmark"
        case .cooldown:
            return "cup.and.saucer.fill"
        }
    }

    /// 스트립에서 탭한 요일이 속한 묶음(같은 규칙 값을 공유하는 요일 집합). 묶음은 값 동등성으로
    /// 정의되므로 표시 순서와 무관하다 — `bundles(from:)` 행 목록의 조회와 결과가 같다.
    static func bundleContaining(day: Int, in rules: [DayRule]) -> (days: Set<Int>, rule: DayRule)? {
        guard rules.indices.contains(day) else { return nil }
        let rule = rules[day]
        return (Set(rules.indices.filter { rules[$0] == rule }), rule)
    }

    /// 7개 DayRule을 값 동등성으로 그룹핑한 묶음 목록. 각 묶음의 첫 요일이 표시 순서에서 나타나는
    /// 순서대로 정렬된다.
    private func bundles(from rules: [DayRule]) -> [WeekdayBundle] {
        var result: [WeekdayBundle] = []
        for index in orderedIndices where rules.indices.contains(index) {
            let rule = rules[index]
            if let existing = result.firstIndex(where: { $0.rule == rule }) {
                result[existing].days.insert(index)
            } else {
                result.append(WeekdayBundle(rule: rule, days: [index]))
            }
        }
        return result
    }

    /// 묶음 요일 라벨. 연속 2일 이상은 "월 ~ 금"처럼 물결로 압축하고, 나머지는 "월, 수, 금"처럼
    /// 쉼표로 나열한다(혼합이면 "월 ~ 수, 금").
    private func daysLabel(for days: Set<Int>) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let ordered = orderedIndices.filter { days.contains($0) }
        guard !ordered.isEmpty else { return "" }

        var runs: [[Int]] = []
        for index in ordered {
            if let lastIndex = runs.last?.last,
               let position = orderedIndices.firstIndex(of: index),
               let lastPosition = orderedIndices.firstIndex(of: lastIndex),
               position == lastPosition + 1 {
                runs[runs.count - 1].append(index)
            } else {
                runs.append([index])
            }
        }

        return runs.map { run -> String in
            if run.count >= 2, let first = run.first, let last = run.last {
                return "\(symbols[first]) ~ \(symbols[last])"
            }
            return run.map { symbols[$0] }.joined(separator: ", ")
        }.joined(separator: ", ")
    }

    /// 묶음의 규칙을 한 줄로 요약("일일 한도 · 30분" — 규칙 종류 포함, 공용 포매터).
    private func ruleSummary(for rule: DayRule) -> String {
        goldTimeDayRuleSummary(rule)
    }
}

// MARK: - 요일 묶음 파생 표현

/// 같은 DayRule 값을 가진 요일들을 묶은 파생 표현. 저장 모델(항상 7개)과 별개로 표시에만 쓴다.
private struct WeekdayBundle: Identifiable {
    var rule: DayRule
    var days: Set<Int>
    /// 요일 집합은 서로 겹치지 않으므로 정렬된 요일 문자열이 안정적인 식별자가 된다.
    var id: String { days.sorted().map(String.init).joined(separator: ",") }
}

/// 묶음 편집 진입 값(value 기반 push). 편집 대상 요일·규칙만 담는 순수 값이라
/// 같은 값을 다시 눌러도 push마다 destination이 새로 만들어진다(@State 신선 보장).
private struct BundleEditContext: Hashable {
    let days: Set<Int>
    let rule: DayRule
}

// MARK: - 주간 스트립

/// 요일 묶음 리스트 상단의 7칸 주간 시각화. 요일마다 규칙 종류를 아이콘으로 보여 주고
/// (제한 있음 accent / 제한 없음 회색 대시), 오늘 요일 라벨은 accent 캡슐로 강조한다.
/// 칸을 탭하면 그 요일이 속한 묶음 편집으로 push. 요일 라벨·순서·칩 시각 언어는
/// `WeekdayChips`와 동일한 규칙을 따른다(List 행 안 다중 버튼도 같은 `.plain` 패턴).
private struct WeekdayRuleStrip: View {
    /// 표시할 요일 인덱스 순서(0=일 … 6=토).
    let orderedIndices: [Int]
    /// 요일 7개 규칙(0=일 … 6=토).
    let rules: [DayRule]
    /// 오늘 요일 인덱스(0=일 … 6=토).
    let todayIndex: Int
    let onSelect: (Int) -> Void

    private var shortSymbols: [String] {
        Calendar.current.veryShortWeekdaySymbols
    }

    private var fullSymbols: [String] {
        Calendar.current.weekdaySymbols
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(orderedIndices, id: \.self) { index in
                column(for: index)
            }
        }
    }

    @ViewBuilder
    private func column(for index: Int) -> some View {
        let rule = rules[index]
        let isToday = index == todayIndex
        let isRestricted = rule.kind != .unrestricted
        Button {
            onSelect(index)
        } label: {
            VStack(spacing: 6) {
                Text(shortSymbols[index])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isToday ? Color.black : Color.secondary)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(isToday ? Color.accent : .clear)
                    .clipShape(Capsule())
                Image(systemName: RuleEditorSheet.stripIconName(for: rule.kind))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isRestricted ? Color.accent : Color.secondary)
                    .frame(height: 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: index, rule: rule, isToday: isToday))
    }

    /// "월요일, 일일 한도 · 30분" / 오늘 칸은 "월요일, 오늘: 일일 한도 · 30분"(기존 키 재사용).
    private func accessibilityLabel(for index: Int, rule: DayRule, isToday: Bool) -> String {
        let summary = isToday
            ? String(localized: "rule.weekday.today \(goldTimeDayRuleSummary(rule))")
            : goldTimeDayRuleSummary(rule)
        return "\(fullSymbols[index]), \(summary)"
    }
}

// MARK: - 요일 묶음 편집

/// 요일 다중 선택 + 규칙 4종(제한 없음/일일 한도/시간대/쿨다운) 선택 + 종류별 파라미터를
/// 한 화면에서 편집한다. 완료 시 선택한 요일에 이 규칙을 쓰고, **이 묶음에서 해제한 요일은
/// 제한 없음이 된다**(applyingBundle 참조).
private struct WeekdayBundleEditView: View {
    let orderedIndices: [Int]
    /// (선택 요일, 진입 시 묶음 요일, 조립된 규칙) — 해제 요일 계산에 initialDays가 필요하다.
    let onSave: (Set<Int>, Set<Int>, DayRule) -> Void

    @Environment(\.dismiss) private var dismiss

    private let initialDays: Set<Int>
    @State private var selectedDays: Set<Int>
    @State private var kind: DayRuleKind
    @State private var limitHours: Int
    @State private var limitMinutes: Int
    @State private var windows: [TimeWindow]
    @State private var cooldownUsage: Int
    @State private var cooldownDuration: Int

    init(
        orderedIndices: [Int],
        initialDays: Set<Int>,
        initialRule: DayRule,
        onSave: @escaping (Set<Int>, Set<Int>, DayRule) -> Void
    ) {
        self.orderedIndices = orderedIndices
        self.onSave = onSave
        self.initialDays = initialDays
        _selectedDays = State(initialValue: initialDays)
        _kind = State(initialValue: initialRule.kind)
        let clampedLimit = min(initialRule.dailyLimitMinutes, 5 * 60 + 55)
        _limitHours = State(initialValue: clampedLimit / 60)
        _limitMinutes = State(initialValue: (clampedLimit % 60 / 5) * 5)
        _windows = State(initialValue: initialRule.timeWindows)
        _cooldownUsage = State(initialValue: initialRule.cooldownUsageMinutes)
        _cooldownDuration = State(initialValue: initialRule.cooldownDurationMinutes)
    }

    /// 로컬 상태를 하나의 DayRule로 조립. 완료 시 이 값을 선택된 요일에 써 넣는다.
    private var composedRule: DayRule {
        switch kind {
        case .unrestricted:
            return DayRule(kind: .unrestricted)
        case .dailyLimit:
            return DayRule(kind: .dailyLimit, dailyLimitMinutes: limitHours * 60 + limitMinutes)
        case .timeWindows:
            return DayRule(kind: .timeWindows, timeWindows: windows)
        case .cooldown:
            return DayRule(
                kind: .cooldown,
                cooldownUsageMinutes: cooldownUsage,
                cooldownDurationMinutes: cooldownDuration
            )
        }
    }

    private var ruleParamInvalid: Bool {
        switch kind {
        case .unrestricted, .dailyLimit:
            return false
        case .timeWindows:
            return TimeWindowPolicy.firstInvalidReason(for: windows) != nil
        case .cooldown:
            return CooldownPolicy.firstInvalidReason(usageMinutes: cooldownUsage, cooldownMinutes: cooldownDuration) != nil
        }
    }

    /// 신규 묶음(+ 추가)은 요일을 골라야 저장할 수 있다. 기존 묶음은 전부 해제도 유효한
    /// 조작이다(= 이 묶음 삭제 → 해당 요일들이 제한 없음이 됨).
    private var canSave: Bool {
        (!selectedDays.isEmpty || !initialDays.isEmpty) && !ruleParamInvalid
    }

    var body: some View {
        List {
            Section {
                WeekdayChips(orderedIndices: orderedIndices, selection: $selectedDays)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } header: {
                Text("rule.weekday.days.header")
            } footer: {
                if selectedDays.isEmpty && initialDays.isEmpty {
                    Text("rule.weekday.selectDaysHint")
                        .foregroundStyle(.red)
                }
            }

            // 규칙 종류는 섹션 타이틀 아래 선택지만 나열한다(picker 라벨이 리스트 행처럼
            // 섞여 보이던 문제 — 라벨은 숨기고 header가 타이틀 역할).
            Section {
                Picker("rule.weekday.kind.header", selection: $kind) {
                    Text("rule.weekday.unrestricted").tag(DayRuleKind.unrestricted)
                    Text("rule.dailyLimit.title").tag(DayRuleKind.dailyLimit)
                    Text("rule.timeWindows.title").tag(DayRuleKind.timeWindows)
                    Text("rule.cooldown.title").tag(DayRuleKind.cooldown)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("rule.weekday.kind.header")
            }

            paramSection
        }
        .navigationTitle("rule.weekday.bundle.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.done") {
                    onSave(selectedDays, initialDays, composedRule)
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(!canSave)
            }
        }
    }

    @ViewBuilder
    private var paramSection: some View {
        switch kind {
        case .unrestricted:
            Section {
                EmptyView()
            } footer: {
                Text("rule.weekday.unrestricted.hint")
            }
        case .dailyLimit:
            Section {
                DailyLimitWheels(hours: $limitHours, minutes: $limitMinutes)
            } footer: {
                Text("rule.dailyLimit.hint")
            }
        case .timeWindows:
            Section {
                ForEach($windows) { $window in
                    TimeWindowRow(window: $window)
                }
                .onDelete { windows.remove(atOffsets: $0) }

                if RuleEditorWindows.canAdd(windows) {
                    Button {
                        RuleEditorWindows.appendWindow(to: &windows)
                    } label: {
                        Label("rule.timeWindows.add", systemImage: "plus")
                    }
                }
            } footer: {
                if let reason = TimeWindowPolicy.firstInvalidReason(for: windows) {
                    Text(reason.userMessage)
                        .foregroundStyle(.red)
                } else {
                    Text("rule.timeWindows.hint \(TimeWindowPolicy.maxWindowCount)")
                }
            }
        case .cooldown:
            Section {
                CooldownWheels(usageMinutes: $cooldownUsage, durationMinutes: $cooldownDuration)
            } footer: {
                if let reason = CooldownPolicy.firstInvalidReason(usageMinutes: cooldownUsage, cooldownMinutes: cooldownDuration) {
                    Text(reason.userMessage)
                        .foregroundStyle(.red)
                } else {
                    Text("rule.cooldown.hint")
                }
            }
        }
    }
}

// MARK: - 일일 한도 본문

private struct DailyLimitDetailView: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    let nearMidnightNotice: String?
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DailyLimitWheels(hours: $hours, minutes: $minutes)
                .padding(.top, 24)

            Text("rule.dailyLimit.hint")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 12)

            if let nearMidnightNotice {
                NearMidnightNoticeBanner(text: nearMidnightNotice)
                    .padding(.top, 16)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .navigationTitle("rule.dailyLimit.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.done", action: onConfirm)
                    .fontWeight(.semibold)
            }
        }
    }
}

/// 일일 한도 시/분 휠 피커. 상세 본문과 요일 묶음 편집에서 함께 쓴다.
private struct DailyLimitWheels: View {
    @Binding var hours: Int
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: 0) {
            Picker("rule.picker.hour", selection: $hours) {
                ForEach(0..<6, id: \.self) { h in
                    Text("common.hours \(h)").tag(h)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Picker("rule.picker.minute", selection: $minutes) {
                ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { m in
                    Text("common.minutes \(m)").tag(m)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 216)
    }
}

// MARK: - 시간대별 차단 본문

private struct TimeWindowsDetailView: View {
    @Binding var windows: [TimeWindow]
    let onConfirm: () -> Void

    private var invalidReason: TimeWindowPolicy.InvalidReason? {
        TimeWindowPolicy.firstInvalidReason(for: windows)
    }

    var body: some View {
        List {
            Section {
                ForEach($windows) { $window in
                    TimeWindowRow(window: $window)
                }
                .onDelete { windows.remove(atOffsets: $0) }

                if RuleEditorWindows.canAdd(windows) {
                    Button {
                        RuleEditorWindows.appendWindow(to: &windows)
                    } label: {
                        Label("rule.timeWindows.add", systemImage: "plus")
                    }
                }
            } footer: {
                if let invalidReason {
                    Text(invalidReason.userMessage)
                        .foregroundStyle(.red)
                } else {
                    Text("rule.timeWindows.hint \(TimeWindowPolicy.maxWindowCount)")
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .navigationTitle("rule.timeWindows.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.done", action: onConfirm)
                    .fontWeight(.semibold)
                    .disabled(invalidReason != nil)
            }
        }
    }
}

/// 시간대 한 칸(시작/종료 DatePicker). 상세 본문과 요일 묶음 편집에서 함께 쓴다.
/// onDelete는 각 화면의 `ForEach`(List Section 직속)에 붙이므로 여기서는 행만 그린다.
private struct TimeWindowRow: View {
    @Binding var window: TimeWindow

    var body: some View {
        VStack(spacing: 8) {
            DatePicker(
                "rule.timeWindow.start",
                selection: RuleEditorWindows.dateBinding(for: $window.startMinuteOfDay),
                displayedComponents: .hourAndMinute
            )
            DatePicker(
                "rule.timeWindow.end",
                selection: RuleEditorWindows.dateBinding(for: $window.endMinuteOfDay),
                displayedComponents: .hourAndMinute
            )
        }
        .datePickerStyle(.compact)
    }
}

/// 시간대 편집 공용 헬퍼(추가 로직 · Date↔분 변환). 상세 본문과 요일 묶음 편집이 함께 쓴다.
private enum RuleEditorWindows {
    static func canAdd(_ windows: [TimeWindow]) -> Bool {
        windows.count < TimeWindowPolicy.maxWindowCount
    }

    /// 다음 시간대를 추가한다. endMinuteOfDay는 inclusive라 직전 종료 분 +1에서 시작해야 겹치지 않는다.
    /// 비면 08:00~08:59. 직전이 12:00–12:59면 새 시간대는 13:00–13:59.
    static func appendWindow(to windows: inout [TimeWindow]) {
        guard canAdd(windows) else { return }
        let start: Int
        if let lastEnd = windows.map(\.endMinuteOfDay).max() {
            start = min(lastEnd + 1, 23 * 60)
        } else {
            start = 8 * 60
        }
        let end = min(start + 59, 24 * 60 - 1)
        windows.append(TimeWindow(startMinuteOfDay: start, endMinuteOfDay: end))
    }

    static func dateBinding(for minute: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { date(fromMinuteOfDay: minute.wrappedValue) },
            set: { minute.wrappedValue = TimeWindowPolicy.minuteOfDay(for: $0) }
        )
    }

    /// 자정 기준 분을 오늘 날짜의 Date로 환산. DatePicker 바인딩에만 쓰며 날짜 성분은 무시한다.
    static func date(fromMinuteOfDay minute: Int) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minute, to: start) ?? start
    }
}

// MARK: - 쿨다운 잠금 본문

private struct CooldownDetailView: View {
    @Binding var usageMinutes: Int
    @Binding var durationMinutes: Int
    let nearMidnightNotice: String?
    let onConfirm: () -> Void

    private var invalidReason: CooldownPolicy.InvalidReason? {
        CooldownPolicy.firstInvalidReason(usageMinutes: usageMinutes, cooldownMinutes: durationMinutes)
    }

    var body: some View {
        VStack(spacing: 0) {
            CooldownWheels(usageMinutes: $usageMinutes, durationMinutes: $durationMinutes)
                .padding(.top, 24)

            Group {
                if let invalidReason {
                    Text(invalidReason.userMessage)
                        .foregroundStyle(.red)
                } else {
                    Text("rule.cooldown.hint")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(.top, 12)
            .padding(.horizontal, 8)

            if let nearMidnightNotice {
                NearMidnightNoticeBanner(text: nearMidnightNotice)
                    .padding(.top, 16)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .navigationTitle("rule.cooldown.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.done", action: onConfirm)
                    .fontWeight(.semibold)
                    .disabled(invalidReason != nil)
            }
        }
    }
}

/// 쿨다운 사용 예산 / 휴식 간격 휠 피커. 상세 본문과 요일 묶음 편집에서 함께 쓴다.
private struct CooldownWheels: View {
    @Binding var usageMinutes: Int
    @Binding var durationMinutes: Int

    // 사용 시간 5분 단위(5분~2시간), 휴식 간격 15분 단위(30분~6시간).
    private let usagePresets = Array(stride(from: 5, through: 120, by: 5))
    private let durationPresets = Array(stride(from: 30, through: 360, by: 15))

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 4) {
                Text("rule.cooldown.usage")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("rule.cooldown.usage", selection: $usageMinutes) {
                    ForEach(usagePresets, id: \.self) { m in
                        Text(Self.label(forMinutes: m)).tag(m)
                    }
                }
                .pickerStyle(.wheel)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Text("rule.cooldown.rest")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("rule.cooldown.rest", selection: $durationMinutes) {
                    ForEach(durationPresets, id: \.self) { m in
                        Text(Self.label(forMinutes: m)).tag(m)
                    }
                }
                .pickerStyle(.wheel)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 216)
    }

    /// 분을 "N분 / N시간 / N시간 M분"으로 표기.
    static func label(forMinutes minutes: Int) -> String {
        if minutes < 60 { return String(localized: "common.minutes \(minutes)") }
        let hours = minutes / 60
        let mins = minutes % 60
        return mins == 0 ? String(localized: "common.hours \(hours)") : String(localized: "common.hourMinute \(hours) \(mins)")
    }
}

// MARK: - 자정 근처 편집 안내 배너

/// 일일 한도·쿨다운 상세에서 자정 근처(23:30+) 편집임을 알리는 배너.
private struct NearMidnightNoticeBanner: View {
    let text: String

    var body: some View {
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
}
