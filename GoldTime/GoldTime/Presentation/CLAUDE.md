# Presentation 레이어

ViewModel + View (MVVM). 화면별 폴더 + 공용 `Component/`. 구성요소는 폴더를 직접 보면 된다.

## ViewModel 패턴 (코드만 봐선 모르는 것)

- `@MainActor @Observable final class XxxViewModel`.
  단 `HomeViewModel`·`StatsViewModel`처럼 계산만 하는 VM은 **순수 struct 허용**.
- DI: UseCase를 생성자에서 `XxxUseCase? = nil`로 받음. nil이면 내부에서 `RepositoryImpl`을
  생성해 UseCase에 주입하여 기본 구현을 만든다.
- **Core 서비스(`ScreenTimeManager`, `AuthorizationService`) 직접 참조 금지** — UseCase만 의존.
- import은 `Foundation`만. `import FamilyControls`는 `AppPickerSheet` 등 FamilyActivityPicker를
  직접 쓰는 화면에서만, `import ManagedSettings`는 `LockOptionsViewModel`의 그룹 토큰 타입
  참조에서만 예외.
- View는 `@Bindable var viewModel: XxxViewModel`(소유는 GoldTimeApp 또는 상위 View).

## Core 직접 참조의 허용 경계 (ADR — 이동 계획 없음)

경계 기준: **집행 로직은 UseCase 경유, 값 읽기·사용자 설정 키·UI 부수효과는 직접 참조 허용.**
잠금·모니터링 상태를 바꾸는 호출(`ScreenTimeManager`, SharedStore의 잠금/override/쿨다운 쓰기)은
반드시 UseCase/Repository로만 태운다. 현재 허용 목록:

- `SharedStore` 값 읽기·설정 키 쓰기: `weekStartDay`(Settings/AppLifecycle),
  `suiteName`(`ContentView` `@AppStorage` store), `max*` 상수(AppPicker/LockOptions),
  프리뷰 통계 시드(`seedForPreview`).
- `SharedStore.drainPendingAnalyticsEvents()`(AppLifecycleViewModel — extension 이벤트 릴레이).
- `ConsentService.shared`(Core/Ads)를 `OnboardingViewModel`·`SettingsViewModel`에서 직접 참조
  (UMP 동의/철회). UseCase 미경유 — UMP 폼 표시는 부수효과만이라 UseCase가 과함.

## UI / 컴포넌트 / 색상

- 기본 iOS 컴포넌트 우선. 날짜/시간·선택·설정·확인은 `DatePicker`/`Picker`/`Form`/
  `confirmationDialog`를 먼저 검토하고, 대체 커스텀 UI는 이유를 남긴다. HIG/iOS 26.0 적합성 확인.
- 공용 컴포넌트는 `Presentation/Component/`(목록은 폴더를 직접 볼 것). 2곳 이상 반복되면
  추출 검토.
- 색상: 새 색은 RGB/hex literal 금지, Asset Color로 추가해 이름으로 사용. `AccentColor`는
  `Color.accent`(Xcode 자동 생성, extension 불필요 — `Color+Brand.swift` 만들면 `invalid
  redeclaration`). 자세히는 `docs/agent/ui-design-system.md`.

톤·문구 판단은 `docs/agent/product-context.md`.

## 주의사항 (작업 중 발견 시 누적)

- **Shield 연장 시트 분석 계약**: `LockOptionsViewModel.onAppear`는 실제 시트 표시 후
  `shield_extend_options_viewed`를 ViewModel 생명주기당 1회 보낸다. `entry_source`는 Shield
  복귀 sheet에서 `shield`, 홈 그룹 카드 sheet에서 `home_group`으로 진입점이 결정한다. 방식 탭은
  `shield_extend_method_selected`, Screen Time 집행 성공·실패는
  `shield_extend_completed`/`shield_extend_failed`로 분리한다. 광고 취소는 선택만 남고
  성공은 남지 않아야 한다. 자동 재시도는 새 사용자 선택이 아니므로
  `method_selected`를 중복 로깅하지 말 것.
- **온보딩 분석 계약**: 앱 정의 이벤트는 `onboarding_entered`/
  `onboarding_completed` 두 개만 보낸다. 단계 전환·Screen Time/알림 권한 결과를 다시
  추가하지 말 것. 둘 다 SwiftUI 재생성·중간 단계 복원에서 부풀지 않게 UserDefaults
  플래그로 설치당 1회만 기록한다. 신규 설치 분모는 Firebase 자동 수집 `first_open`.
- **권한 분석 계약**: `AppLifecycleViewModel.appDidBecomeActive()`는 Screen Time 상태를
  refresh하고 알림 상태를 await한 뒤 `authorized_screen_time`/
  `authorized_notification`을 매 활성화마다 갱신한다. 미승인자도 갱신 guard 밖에
  두어 `false`로 덮어써야 한다. 이벤트로 바꾸거나 그룹 코호트의 권한 guard 안에 넣지 말 것.
  **`appDidBecomeActive()`의 호출 순서는 "user property 갱신 → 이벤트 전송"이 계약이다**
  (2026-08-18 수정). Firebase property는 **설정 이후에 전송된 이벤트에만** 붙으므로, 권한 갱신을
  `logGroupSnapshots()`/`drainPendingAnalyticsEvents()` 뒤로 미루면 이번 활성화의 이벤트가
  직전 세션 값을 달고 나가고 **신규 설치의 첫 활성화에는 권한 속성이 아예 없다** — 권한별
  그룹 구성 분석에서 첫 세션이 통째로 빠진다. `await`라고 뒤로 밀지 말 것. 반대로 UI 경로
  (`syncProtectionRulesIfAuthorized`·`refreshLockOptionsPresentation`)는 **await보다 앞**에 둔다
  (Shield 복귀 시트가 알림 권한 조회를 기다리게 되면 안 된다).
- **그룹 규칙 스냅샷 계약**: 앱 활성화마다 적용 그룹 하나당 `rule_uniform_*` 또는
  `rule_weekday_snapshot` 하나를 보낸다. `weekday`는 실제 규칙 종류가 아니라 적용 방식이고,
  `strict_lock_active`는 규칙과 독립된 상태다. 반복 전송 때문에 GA4 채택률은 이벤트 수가 아닌
  총 사용자 수로 비교한다. `group_snapshot`과 규칙 이벤트들은 활성화마다 새로 만든 동일한
  `snapshot_id`를 공유해야 한다. 각각 UUID를 만들면 대시보드가 최신 배치의 여러 그룹을 복원하지 못한다.
- **그룹 수/행동 분석 계약**: Screen Time 권한이 있는 매 앱 활성화에 `group_snapshot`을
  한 번 보내며 적용 그룹 0개도 누락하지 않는다. 사용자 행동은 적용 저장 후
  `group_applied`, 삭제 저장 후 `group_deleted`만 남기고 draft 생성·규칙 변경·내부 sync는 수집하지 않는다.
  구 사용자 속성 `active_group_count`는 중복이라 폐기했으며, 업그레이드 사용자의 stale 값을
  없애기 위해 코호트 갱신 시 nil로 지운다.
- **`LockOptionsView`/`LockOptionsViewModel.onAppear`의 `entrySource`에 기본값을 두지 말 것.**
  `shield_extend_options_viewed.entry_source`는 Shield 액션 퍼널의 **분모**라, 새 진입점이
  인자를 깜빡 생략하면 홈에서 연 시트가 조용히 `shield`로 집계돼 퍼널이 틀어진다. 컴파일 에러로
  매번 결정을 강제한다(기본값 `.shield`가 있던 시절의 회귀 방지).
- **연장 불가 완료 분석 계약**: 시작·연장 성공 때 최초 시작·최종 만료를 분석 저장소에 갱신하고,
  `AppLifecycleViewModel`은 권한이 유지된 첫 만료 후 활성화에서 `strict_lock_completed`를 한 번
  보낸다. 과거 만료 그룹을 훑어 소급 생성하면 안 된다.
  **미승인 활성화는 전송만 건너뛰고 약정을 폐기하지 않는다**(2026-08-17 수정 — 폐기하던 구현이
  버그였다): `refresh()` 직후의 `isAuthorized`는 콜드 스타트에서 transient `false`로 읽힐 수 있고
  (복구 UI가 재확인을 요구하는 것과 같은 이유), 폐기는 되돌릴 수 없어 한 번만 잘못 읽혀도 진행 중
  약정까지 사라진다 → 그 사용자는 영영 완료를 안 보내고 완주율의 **분자만 조용히 깎인다**.
  폐기는 철회 증거가 있는 경로(`ContentViewModel.handleScreenTimeRecoveryAppear` — 복구 화면 도달)에서
  `discardStrictLockCommitments(groupIDs:)`로 그룹을 특정해서만 한다. "전부 지우기" API를 되살리지 말 것
  (회귀 테스트 `unauthorizedActivationKeepsPendingStrictLockCommitments`).

- **연장 불가 모드(기간 강력 잠금) UX 계약**: 진입 차단은 ContentViewModel 3곳
  (`presentRuleEditor`/`requestPickerPresentation`/`requestDeleteGroup`) + `deleteGroup`의
  Domain(`ManageGroupsUseCase.deleteGroup`) 경유가 세트다 — 새 편집/삭제 진입점을 만들면 같은
  guard(`isStrictLockActive` + `strictBlockedAlert`)를 반드시 추가한다. **연장 불가 기간 판정은 항상 원본
  그룹**(`resolved(on:)` 투영은 strict 필드가 스트립됨 — `LockOptionsViewModel`의
  `selectedGroup?.resolved(...)` 체인에 판정을 얹지 말 것). 연장 불가 시트(`StrictLockSheet`)의
  강한 확인 2단계는 **같은 시트 안 콘텐츠 전환**이다(시트 안 dialog→modal 연쇄 금지 규칙).
  켜기는 무료(광고 없음 — "강화는 무료, 완화에 통행료"), 이름 변경(`updateName`)만 연장 불가 기간 중에도
  허용. **만료 표기는 `goldTimeStrictLockedUntilText` 공용** — 저장값 `strictUntil`은 자정 경계라
  그대로 쓰면 "7/14 0시에 풀려요"처럼 하루 밀린 느낌이 든다. 1초를 빼 마지막 잠금 날을 뽑고
  문구는 "%@ 23:59까지 연장 불가"로 통일한다(시각 리터럴은 문구 키 안에). 시작일 등 "날짜 자체"는
  `goldTimeShortDateText`. **기능 게이트는 남아 있지만 베타 기간엔 항상 열려 있다**(2026-08-15 —
  설정 토글 제거): `ManageGroupsUseCase.isStrictLockEnabled`(= `true`) →
  `ContentViewModel.isStrictLockFeatureEnabled` → `GroupCardView`. 정식 출시 때 이 프로퍼티만
  **구독 entitlement 판정으로 갈아끼우면** 카드 노출·`presentStrictLockSheet`·`activateStrictLock`
  guard가 그대로 페이월이 된다 — 게이트 체인을 "어차피 true니까"라며 지우지 말 것. 구 토글 저장값
  (`SharedStore.isStrictLockEnabled`)은 **읽지 않는다**(Off로 저장돼 있던 기존 사용자가 업데이트 후
  못 쓰게 된다 — 회귀 테스트 `strictLockAvailableEvenWhenLegacyToggleValueIsOff`). 설정에 토글을
  되살리지 말 것: 유료 전환 전 "써 보고 가치를 느낀 사용자" 모수를 스스로 깎고, 페이월도 설정보다
  카드 행(쓰려고 손을 뻗는 자리)에 서는 게 맞다.
  **게이트는 "새로 걸기·연장"만 막는다 — 이미 걸린 기간은 게이트와 무관하다.** 집행부(편집·연장
  차단, Shield, `denyAppRemoval` 전역 설정, extension 전부)는 게이트를 **한 번도 참조하지 않고**
  `strictUntil`만 본다. 그래서 게이트를 닫아도 진행 중인 잠금은 안 풀리고, 행 노출을 게이트만으로
  결정하면 **잠긴 채 만료일만 못 보는** 상태가 된다 → `HomeViewModel.showsStrictRow(for:featureEnabled:)`가
  `featureEnabled || isStrictLocked`로 판정한다(회귀 테스트
  `strictRowStaysVisibleWhileLockedEvenIfGateClosed`). 구독 페이월이 붙으면 **구독 만료로 게이트가
  닫히는 경로**가 실제로 생기는데 이건 사용자 액션이 아니라 시스템 이벤트라 "끄기 금지" 같은 UI
  방어로는 못 막는다 — 구 설정 토글의 끄기 방어(`setStrictLockEnabled` false 반환)를 되살리는 대신
  이 계약을 지킬 것. 구독 해지로 잠금이 풀리면 "해지하면 풀린다"는 탈출구를 알려주는 셈이라
  "권한 끄면 풀린다"를 켜기 화면에 안 적는 규칙과 같은 이유로 금지다.
  **연장 불가 그룹에서는 광고 게이트 다이얼로그를 절대 먼저 띄우지 않는다**(`GroupCardView`의
  `tapEditSelection`·trash 분기): "광고 보고 편집하기"는 연장 불가 모드와 모순되는 안내이고, 다이얼로그가
  닫히는 사이클에 차단 alert를 세팅하게 돼 SwiftUI가 alert 표시를 건너뛴다 — 곧장 ViewModel
  guard로 보내 alert만 띄운다. 연장 불가 시트 진입은 **applied + 유효 규칙**일 때만 연다
  (`presentStrictLockSheet` — 무효 그룹을 열어주면 `activateStrictLock`이 거부해 최종 확인을
  눌러도 조용히 실패하고 사용자는 켜졌다고 오인한다). 확정 실패 alert은 시트 dismiss와 겹치지
  않게 `Task { @MainActor }`로 미룬다. **켜기 화면에 "권한을 끄면 풀린다"는 고지를 다시 넣지
  말 것**(2026-07-13 제거) — 사실이지만 잠그려는 순간에 탈출 방법을 알려주는 셈이다. 권한 철회는
  이미 풀린 뒤의 복구 화면(`recovery.strictNotice`)에서만 다룬다.

- **연장 불가 모드 표기 계약(2026-07-29 실사용 피드백 반영 — 되돌리지 말 것)**: ① 카드의 연장 불가
  행 제목은 **적용 전/후 두 키**다(`group.strictRow.title.inactive` "연장 불가 기간 설정" /
  `.active` "연장 불가 기간") — 규칙 행("차단 규칙 선택" → "일일 한도"/"30분")과 같은 문법이라
  적용 중 제목은 **라벨이고 값(만료일)은 부제가 맡는다**. 한 키로 합치면 이미 걸렸는지를
  부제로만 판별하게 된다. 어휘는 "모드"가 아니라 **"기간"**으로 통일한다(2026-08-15 변경):
  카드에서 하는 일은 기간(1/3/7일) 선택이고 "모드"는 기능 전체의 이름이라, 행 제목이 "모드"면
  기능을 켜라는 뜻으로 읽힌다(설정 토글이 있던 시절엔 이미 켠 기능을 또 켜라는 말이 됐다).
  기능 전체를 가리키는 자리(베타 안내·팝오버 본문)에서만 "연장 불가 모드"를 쓴다.
  **적용 중 제목에 "-중"을 붙이지 말 것**(구 "연장 불가 중"·"연장 불가 적용 중"):
  "-중"은 동작 명사에 붙는 접미사인데 "연장 불가"는 상태라 어색하고("불가능 중"), 진행 중이라는
  신호는 자물쇠 아이콘·만료일 부제·"N일 남음" 배지가 이미 세 번 말한다. "적용"은 그룹
  적용(`isApplied`)과 겹치는 말이라 더 쓰지 않는다. ② 배지는 **"N일 남음"**
  (`home.badge.strict %lld`) — **D-N 표기 금지**(D-day 관습상 "연장 불가가 N일 뒤 시작"으로
  읽힌다). 자물쇠 아이콘이 무엇이 남았는지 말하므로 배지 문구에 "연장 불가"를 다시 넣지 않는다.
  배지는 `Label`이 아니라 `HStack(spacing: 3)`으로 조립한다(Label은 아이콘–텍스트 간격을 제어할
  수 없어 자물쇠 오른쪽 여백이 뜬다). ③ **만료 안내는 날짜를 문장 앞에** 둔다("%@ 23:59까지는
  바꿀 수 없어요") — "…끝나야 바꿀 수 있어요. 7/13 23:59까지." 같은 도치는 두 번 읽게 된다.
  ④ 기간 기본값은 `ManageGroupsUseCase.strictLockDefaultDays`(**1일 — 가장 짧은 프리셋**,
  2026-07-31 변경)이라 시트가 "1일 칩 선택 + 휠 접힘"으로 열린다. 한 번 걸면 못 푸는 모드라
  처음 화면이 긴 기간을 권하면 안 된다 — 기본값을 프리셋 밖 값으로 되돌리지 말 것. 커스텀 칩을
  누를 때만 `strictLockCustomSeedDays`(14일, 프리셋 밖 값)로 휠이 펼쳐진다(회귀 테스트
  `strictLockDefaultDaysStartsOnShortestPresetChipAndCommits`). ⑤ 기능 설명은 **카드 연장 불가 행의
  제목 옆 24×24pt 인포 버튼**에서 제목 없는 2문단 팝오버로 꺼낸다(`group.strictRow.info` — 설정
  행에서 옮겨 옴, 2026-08-15). 행에 긴 부제를 달지 말고 팝오버로 보낼 것. 이때 **행 전체 탭은
  `Button`이 아니라 `onTapGesture`로 받는다**: 부모 `Button` 안에 인포 `Button`을 중첩하면 부모가
  먼저 히트돼 팝오버 대신 시트가 열린다(접근성은 `accessibilityElement(children: .combine)` +
  `.isButton` trait로 보전). ⑥ 설정 행에 있던 발광 테두리(`StrictLockGlowBorder`)는 행과 함께
  제거했다(2026-08-15) — 그 연출은 "설정 깊숙이 숨어서 안 보임"을 보정하려던 장치였고, 카드 행은
  홈 메인이라 필요 없다. 카드로 되살리면 적용 그룹 수만큼 동시에 회전·발광해 시끄러워진다.
- **확정 순간의 피드백**: `confirmStrictLock` 성공 시 시작/연장 alert(`content.alert.strictStarted.*`
  /`.strictExtended.*`, 확정 **전** `isStrictLockActive`로 분기)을 띄우며 `LockFeedback.play()`
  (Core/Feedback)를 함께 재생한다. 둘 다 **시트가 닫히는 사이클과 겹치면 누락**되므로 실패
  alert과 같은 `Task { @MainActor }` 지연 안에서 실행한다. `Core/Feedback`의 사운드·햅틱은
  Presentation에서 **직접 참조 허용**(집행이 아닌 UI 부수효과 — `PurchaseFeedback`을 쓰는
  `LockOptionsViewModel`이 선례).
  **잠금은 소리 없이 햅틱만**이다(묵직한 두 박, 2026-07-31 채택) — 시스템 사운드 3종·번들 음원
  7종을 실기기 청취로 전부 기각한 결과이고 기각 이력은 `LockFeedback.swift` 상단 주석에 있다.
  "잠금음이 없다"를 버그로 보고 채우지 말 것. 광고 연장(`PurchaseFeedback`)만 소리를 내며,
  **소리 유무 자체가 두 이벤트의 대비**다(연장=소리+success 햅틱 / 잠금=햅틱만).

- **자정 직전 안내는 경계가 둘이고 서로 다르다(헷갈리기 쉬움)**. 편집 중 RuleEditor 안 인라인
  notice(`ContentViewModel.nearMidnightEditNotice` / `isNearMidnightEditNoticeWindow`)는 **23:30**부터
  예고용으로 뜨고, 규칙 적용·수정 **직후** alert(`nearMidnightApplyNotice` / UseCase
  `isNearMidnightMonitorTooShort`)은 실제 모니터 등록이 `intervalTooShort`로 막히는 **23:45**부터만
  뜬다(Core의 `overrideWindowTooShort` 경유). alert은 **일일 한도·쿨다운만** — 시간대 차단은
  측정창과 무관해 제외(`commitTimeWindowsRule`은 안 건드림). 커밋 경로의 alert은 여기에 더해
  **오늘 투영(`resolved(on:)`)이 실제로 바뀔 때만** 뜬다(`changesTodayProjection` — 오늘 투영이
  그대로면, 예: 다른 요일만 편집·무변경 완료, `syncDailyMonitoring`의 churn 가드가 재등록을
  건너뛰어 미추적 갭이 없는데 안내가 뜨는 false positive가 된다; 1.2.0 요일별 규칙에서 실제 발생).
  적용하기(`confirmApplyGroup`) 경로의 alert은 확인 다이얼로그가 닫히는 사이클과 겹쳐 누락되지
  않도록 `Task { @MainActor }`로 미뤄 띄운다.
- **[해결 불가 / API 한계] FamilyControls `Label(token)` 아이콘 크기**: 시스템이 렌더하는 뷰라
  `.frame`·`.font`은 무시되고 `.scaleEffect`만 먹힌다(확대 시 흐려짐). 게다가 기본 렌더 크기·여백이
  **토큰 종류(앱/웹)·기기·OS마다 제각각**이다(애플 포럼 thread 721432: iPhone 14 Pro ~20px+여백,
  XS/iPad ~40px+여백없음 / thread 731387: 애플도 미해결, Feedback Assistant 권장). 시도해 본 우회책
  모두 다른 문제를 유발 → 고정 `scaleEffect` 값은 OS별로 잘림/축소, GeometryReader 동적 측정은
  앱/웹 시각 크기 불일치, `fillScale` 여백 보정은 기기마다 깨짐. **완벽한 크기 통일은 불가능**으로
  결론. GroupCardView·LockOptionsView 모두 각자 `tokenIcon(_:)` 헬퍼로 OS별 라벨 체인을 통째로
  분기한다: iOS 26+는 `scaleEffect+frame+clip`(기본이 작아 키움), iOS 26 미만은 쌩 라벨 +
  `padding`(기본이 커서 키우면 잘리므로 간격만). 크기만 화면별로 다르다(GroupCard 28, LockOptions는
  작은 요약이라 20). 애플이 토큰 아이콘 크기 제어 API를 제공하기 전까지 더 손대지 말 것.
- Screen Time 복구 full-screen cover는 `AuthorizationCenter` 상태를 refresh하는 중의 transient
  `false`에 반응하면 깜빡인다. 초기 체크·observer 초기 콜백·`loadState()` refresh는 상태만 갱신하고,
  복구 UI는 홈 진입 후 재확인/권한 요청까지 실패해 미승인이 확정된 경로에서만 띄운다.
- **로컬라이징은 semantic key 방식**(키 = `domain.screen.element` dot-notation, 값 = `Localizable.xcstrings`의 ko). 코드에 한국어 리터럴을 직접 쓰지 말고 키만 쓴다. 두 갈래: View의 `Text`/`Button`/`Label`/`.navigationTitle`/`Picker`/`DatePicker`/`.confirmationDialog`는 `LocalizedStringKey`를 자동으로 받으니 `Text("home.title")`처럼 키만, ViewModel 계산 속성·동적 메시지·`ShieldConfiguration.Label`은 `String(localized: "key")`. 보간은 `"key \(value)"` → 카탈로그 키가 `"key %lld"`(Int)·`"key %@"`(String), 값은 위치 지정자 `%1$@ %2$lld`. 키 추가는 코드 전환 후 `python3`로 `Localizable.xcstrings`에 병합(`extractionState:"manual"`, ko `state:"translated"`).
- **재사용 컴포넌트의 텍스트 파라미터는 반드시 `LocalizedStringKey`로 받는다**(`SectionHeader.title`, `OnboardingStepView.title`, `RuleEditorSheet.ruleRow`, `NotificationSettingsView.toggleRow` 등). `String`으로 받으면 내부 `Text(param)`이 **verbatim**이라 키 문자열(`"settings.title"`)이 화면에 그대로 노출된다 — 컴파일은 통과해 시뮬/실기기로만 잡힌다. 예외: 파라미터 값이 이미 `String(localized:)`로 번역된 동적 문자열이거나(`DashboardMetricCard.title/value`처럼) `subtitle`이 ViewModel computed `String?`이면 `String`으로 받고 호출부에서 `String(localized:)`로 만든다. `Text(someStringVar)`는 항상 verbatim임을 기억.
- enum의 `rawValue`를 화면에 직접 쓰면(`Text(mode.rawValue)`) 로컬라이징 안 된다 → `var title: LocalizedStringKey` 같은 별도 프로퍼티로 분리(`Text(mode.title)`). 이모지·숫자식별자는 `Text(verbatim:)`로 키 추출/조회를 피한다.
- **통계 카드의 추세(화살표·색)·delta 문구는 반드시 표시값과 같은 올림 분 단위로 비교한다**(`StatsViewModel.displayTrend`/`displayMinutes`, `todayDeltaCaption`/`weeklyDeltaCaption`). 카드 값은 `goldTimeDurationText`가 **올림 분**으로 보여주므로, 추세를 초 단위 delta나 합계로 판단하면 표시값과 어긋난다 — `14분인데 ↑빨강`(합계 비교 회귀), `둘 다 15분인데 "1분 적어요"`(초 단위 비교) 같은 버그. 하단 기록 섹션(`StatsComparison`)도 같은 `displayMinutes` 분 단위 비교를 쓴다. Domain `StatsReport`는 raw 초 단위 평균만 노출하고(`weeklyAverageSeconds` 등) **추세 판단은 ViewModel이 분 단위로** 한다 — `StatsReport`에 trend/합계 delta를 도로 넣지 말 것. 표시값-화살표 일치는 단위 테스트로 잡히지만(`statsViewModelWeeklyTrend*`) 실기기 색·방향은 시뮬/실기기로만 확인.
- **규칙 편집 광고 게이트는 진입이 아니라 완료(커밋) 시점이다**(`ContentViewModel.commitRuleSelection` → `requiresAdForRuleCommit`): 적용(applied) 그룹 + **집행 영향 변경**일 때만 광고를 요구한다. 보기만 하는 진입·무변경 완료·`isExplicitlyUnrestricted` 승격만 있는 커밋(표시 전용)·draft 그룹은 무료. **냅다 광고를 띄우지 않는다** — 안내와 광고를 **하나의 fullScreenCover 안 2단계**로 전환한다(`ContentView`의 `RuleCommitAdGateView`: 1단계 하단 확인 카드 "광고 보고 변경하기"/취소·배경 탭=취소 → 2단계 `RewardedAdView`). 시트 안 confirmationDialog → cover 연쇄는 어떤 타이밍 처방으로도 글리치가 남아 폐기했다(아래 presentation 타이밍 항목 참조). 어느 단계서 취소해도 편집 내용이 유지되고, 실제 커밋은 cover의 onDismiss(`handleRuleCommitAdGateDismiss`)에서 수행한다 — cover와 시트가 같은 사이클에 dismiss되면 staged alert(즉시 잠금 경고·자정 안내)가 누락되는 함정 때문. 무효한 요일 상태는 광고 없이 `performRuleCommit`으로 보내 기존 검증 alert 경로를 태운다(광고 낭비 방지). 즉시 잠금 경고는 광고 **뒤**에 뜬다(기존 staged 흐름 유지) — 경고에서 취소하면 광고가 소모되는 엣지는 수용된 트레이드오프. 앱 선택 편집·삭제는 여전히 진입 전 게이트(`requestPickerPresentation`/`requestDeleteGroup`). placement는 `groupEditGate` 재사용이라 GA4 `group_edit_gate` 노출 의미가 '편집 진입'→'변경 적용'으로 바뀌었다(대시보드 해석 주의).
- **SwiftUI presentation 전환 타이밍 — 위치(호스트)에 따라 처방이 다르다(반복 회귀 이력, 헷갈리면 여기부터)**: ① 다이얼로그 버튼 → 다음 presentation(sheet·fullScreenCover) 전환은 **호스트가 어디냐가 결정한다**. **루트 호스트**(메인 화면의 다이얼로그 → 루트 `.sheet`)는 같은 트랜잭션에서 즉시 플래그를 세우면 SwiftUI가 dismiss → present를 순차 처리한다(삭제 다이얼로그 → 광고 시트 — 동작 실증). 그러나 **시트 안(nested presentation host — 규칙 편집기처럼 `.sheet` 내용에 다이얼로그와 cover가 함께 붙은 경우)에서는 이 순차 처리가 깨진다**: 즉시 세팅도, 한 런루프 `Task` 지연도 dismiss 애니메이션(수백 ms) **도중에** UIKit present가 시도돼 콘솔 "Attempt to present … which is already presenting"과 함께 거부되고 **modal이 영영 안 뜬다**(1.2.0 완료 광고 게이트에서 두 방식 모두 실측 실패). dismiss 애니메이션을 넘기는 지연(0.6s)으로 거부는 피해도 이번엔 **닫힌 다이얼로그가 한 번 더 떴다 사라지는 재표시 글리치**가 남고, 확인/취소 액션에서 `isPresented` 명시적 false를 세팅해도 못 잡았다(총 실측 3회). **최종 처방: 시트 안에서는 다이얼로그 → 다음 modal 연쇄를 아예 만들지 말 것 — presentation 하나(fullScreenCover) 안에서 콘텐츠 단계 전환으로 푼다**(`RuleCommitAdGateView`). 루트 호스트의 즉시 세팅 패턴(삭제 다이얼로그 → 광고 시트)은 그대로 유효하다. ② **시트/다이얼로그가 "닫히는 것과 같은 업데이트 사이클"에 `.alert`를 띄우면** SwiftUI가 표시를 건너뛴다 → staged 상태로 두고 `onDismiss` 훅에서 승격하거나(`handleRuleEditorDismiss`·`handleAdGateDismiss`), 그게 안 되는 자리면 `Task { @MainActor }`로 다음 런루프에 미룬다(`presentDeletionCompletedAlert`). **요약: alert 누락은 "onDismiss/한 런루프", 시트 안 modal 연쇄는 "애니메이션 넘긴 지연" — 한 런루프 지연은 후자에겐 최악의 타이밍이다.** 이 타이밍 버그들은 단위 테스트로 못 잡고 시뮬/실기기에서만 드러난다.
- **요일 편집 UX의 '제한 없음'은 두 갈래다(`RuleEditorSheet`)**: implicit(토글 시드·요일 그룹에서 요일 해제, `isExplicitlyUnrestricted == false`)은 요일 그룹 행을 만들지 않고 스트립 회색 대시로만 보이고, explicit(편집 화면에서 '제한 없음'을 직접 골라 저장)만 행이 된다(`visibleBundles`). **주간 스트립 탭은 어느 요일이든 그 하루만 선택 + 그 요일의 현재 규칙으로 진입**(`tapEditTarget` — 같은 규칙을 공유하는 요일이 딸려 오지 않는다; 여러 요일 일괄 변경은 요일 그룹 행 진입이 담당), **무변경 완료도 explicit 승격 → 행 생성(의도된 동작 — '완료' = 직접 설정)**. 신규(draft) 그룹 토글 ON은 implicit 7개 시드(`seededWeekdayRules`, 행 0개 시작), 기존 규칙 그룹은 base 규칙 × 7 시드. 단 **같은 시트 세션에서 토글 OFF→ON은 재시드가 아니라 보관본 복원**(`stashedWeekdayRules` @State — OFF 때 편집 내용을 보관, 시트가 닫히면 소멸). `allUnrestricted` 무효 상태의 footer는 빨간 에러가 아니라 중립 안내(`rule.weekday.empty.footer`)이며 완료 disabled는 유지 — 이 분기를 없애고 에러로 통일하지 말 것(빈 시작 상태가 곧바로 빨간 에러로 보인다). **UI 용어는 "요일 그룹"**(구 "요일 묶음" — 코드 타입명 `WeekdayBundle` 등은 앱 그룹 `ScreenTimeGroup`과의 혼동을 피해 Bundle 유지). 규칙 편집 시트는 진입이 무료라 **인터랙티브 dismiss(드래그/배경 탭 = 취소) 허용**(`interactiveDismissDisabled` 다시 달지 말 것 — 진입 전 게이트인 AppPickerSheet와 다르다).
- **요일 라벨은 `veryShortWeekdaySymbols` 대신 `shortWeekdaySymbols`를 쓴다**. 영어의 very-short 표기는 토·일이 모두 `S`라 규칙 편집에서 모호하다. `shortWeekdaySymbols`는 한국어·일본어에서는 짧은 한 글자 표기를 유지하고, 영어에서는 `Sun`·`Sat`처럼 구분되는 표기를 제공한다. 칩·주간 스트립·요일 그룹 요약은 반드시 같은 배열을 쓴다.
