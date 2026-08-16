# Domain 레이어 — 가장 엄격

순수 Swift. Model, Repository 프로토콜, UseCase, Policy. 아무 레이어도 의존하지 않는다.
구성요소는 하위 폴더를 직접 보면 된다.

## import 규칙 (코드만 봐선 모르는 것)

- 기본은 **`Foundation`만**. 아래 파일별 예외 외에는 프레임워크 import 금지.
- `ManagedSettings` 예외: `Repository/ShieldRepository.swift`,
  `UseCase/ExtendGroupUseCase.swift` — Shield 토큰 타입(`ApplicationToken`/`WebDomainToken`)이
  시그니처에 필요.
- `FamilyControls` 예외: `UseCase/ManageGroupsUseCase.swift` — `FamilyActivitySelection` 파라미터.
- `UIKit` 예외: `Repository/AdRepository.swift` — 광고 표시 anchor로 `UIViewController`를
  프로토콜 시그니처에 노출(광고 SDK 계약상 불가피).
- 예외 파일에서도 Apple 토큰/선택 타입은 **opaque 값으로 시그니처 통과만** 한다 — Domain에서
  내용을 해석하거나 로직 분기하지 않는다.
- `ScreenTimeManager`, `AuthorizationService` 등 Core 서비스 **직접 참조 금지**.

## 패턴

- Repository는 **프로토콜만** 선언. 구현체(`Impl`)는 Domain에 없다(Data에 있다).
- UseCase는 `final class`, Repository를 생성자에서 `any RepositoryProtocol`로 주입.
- 상태 관리에 `@Observable`·`@Published` **사용 금지**(순수 값/참조 타입).

## 유지 결정 (기술 부채 아님 — ADR)

- `Domain/Model/ScreenTimeGroup.swift`의 `typealias ScreenTimeGroup = SharedStore.ScreenTimeGroup`은
  **유지한다**(Domain 독립 타입으로 분리하지 않는다). App Group Codable 하위 호환과 extension
  타겟 파일 공유 때문에 원본이 SharedStore에 사는 게 맞고, 분리는 매핑 계층만 늘린다.
  `ManageGroupsUseCase`의 `SharedStore.maxGroupCount` 같은 상수 참조도 같은 이유로 허용.
  배경: `docs/agent/decision-context.md`의 ADR.

## 비즈니스 규칙

- **유효한 그룹** = 적용됨(`isApplied`) + 앱/웹사이트 1개 이상 + 규칙 유효(일일 한도 0분 이상,
  시간대는 TimeWindowPolicy 통과) + 앱+웹사이트 합산 그룹당 제한 이내. draft·미완성 그룹은
  저장하되 모니터링에서 제외.
- 시간대(TimeWindow)는 **그룹당 최대 3개, 15분 이상, 자정 넘김 금지**.

레이어 의존 다이어그램·새 파일 배치는 `docs/agent/architecture.md`.

## 주의사항 (작업 중 발견 시 누적)

- **Shield·연장 분석 계약**: 집행 시작은 `shield_lock_started`, 시스템 Shield
  버튼은 `shield_action_*`, 앱 연장 시트는 `shield_extend_*`로 계층을 나눈다.
  성공은 1분·광고를 `shield_extend_completed` 하나로 합치고 `extend_method`로 나눈다.
  `rule_mode`는 저장 방식, `enforcement_rule`은 오늘 실제 집행 규칙이다. 요일별 그룹에서
  둘을 합치거나 구 `ad_unlock`·`one_minute_unlock`을 다시 추가하지 말 것.
- `AuthorizationAnalyticsProperties`는 앱 활성화 시점의 권한 스냅샷이다.
  `authorized_screen_time`/`authorized_notification`은 Firebase user property 제약에 맞춰
  문자열 `true`/`false`로 보낸다. 알림의 `authorized`·`provisional`·`ephemeral`은
  `true`, `denied`·`notDetermined`·`unknown`은 `false`로 묶는다.
- `RuleGroupSnapshotAnalytics`에서 실제 규칙은 `rule_uniform_daily`/
  `rule_uniform_time_window`/`rule_uniform_cooldown`, 적용 방식은 `rule_weekday_snapshot`,
  연장 불가는 `strict_lock_active`로 서로 다른 축에 둔다. 요일별 그룹은 `weekday_uses_*`와
  `weekday_*_days`로 내부 규칙을 보존하며 days 네 값의 합이 7이어야 한다. 그룹 UUID·이름은
  보내지 않는다.
- `group_snapshot.applied_group_count_bucket`은 최대 그룹 수가 5개라 `0`~`5`의 정확한 문자열 값을
  보낸다. `4+`처럼 합치면 4개와 5개 사용자를 구분할 수 없으므로 다시 버킷화하지 말 것.
- `UserCohortProperties`의 `active_rule_profile`/`strict_rule_profile`은 `wdN_dlN_twN_cdN` 형식으로 **top-level 그룹 수**만 센다. 요일별 그룹 안의 일일/시간대/쿨다운 요일을 별도 그룹으로 세거나, 그룹명·UUID·선택 앱을 넣지 말 것. strict는 `isApplied && isStrictLockActive(at:)`인 그룹만 포함한다. 새 규칙 종류를 추가하면 `RuleGroupProfile`과 이 분석 계약을 함께 갱신한다.
- 적용 그룹 수는 앱 활성화 이벤트 `group_snapshot.applied_group_count_bucket`의 정확한 `0`~`5`로만 본다. 구 사용자 속성 `active_group_count`는 같은 상태를 거친 버킷으로 중복해 폐기했으므로 다시 추가하지 말 것.
- 연장 불가 분석은 `strict_lock_started`/`extended`/`completed`/`revoke_detected`로 나눈다. `revoke_detected`는 권한 철회 순간이 아니라 복구 화면에서 관측한 결과다. 완료의 `strict_lock_days`는 최초 시작일~최종 만료일의 총 기간이며, 시작·연장의 값은 해당 선택에서 추가한 기간이라 의미가 다르다.
- **연장 불가 기간 중 편집 차단은 `ManageGroupsUseCase`의 update 3종(`updateRule`/`updateWeekdayRules`/`updateSelection`)과 `deleteGroup`의 guard가 담당한다**(조용히 무시 패턴 — `updateName`은 집행 무관이라 의도적으로 제외). 그룹을 변경하는 새 UseCase 메서드를 추가하면 같은 `isStrictLockActive()` guard를 반드시 넣을 것. `activateStrictLock`은 **범위(`strictLockDayRange` 1...30) 검증**(프리셋 검증이 아니다 — 커스텀 기간이 정상 경로) + applied·유효 규칙만 + **연장만 허용(만료 축소 거부)** + 최초 `strictStartedAt` 유지. 칩 프리셋은 `strictLockDayPresets`(1/3/7)이고 시트 기본 선택은 `strictLockDefaultDays`(1 — **가장 짧은 프리셋이어야** 시트가 "1일 칩 선택 + 휠 접힘"으로 열린다, 2026-07-31 변경). 커스텀 칩을 눌렀을 때 휠이 잡는 시드는 별개 상수 `strictLockCustomSeedDays`(14)이고 이쪽은 반대로 **프리셋에 없어야** 커스텀 칩 선택 상태가 유지된다. `ExtendGroupUseCase`의 strict 판정은 원본 그룹(`shieldRepository.lockedGroups()`) 기준이다 — resolved 투영은 strict 필드가 스트립되므로 판정에 쓰지 말 것.
