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

- `UserCohortProperties`의 `active_rule_profile`/`strict_rule_profile`은 `wdN_dlN_twN_cdN` 형식으로 **top-level 그룹 수**만 센다. 요일별 그룹 안의 일일/시간대/쿨다운 요일을 별도 그룹으로 세거나, 그룹명·UUID·선택 앱을 넣지 말 것. strict는 `isApplied && isStrictLockActive(at:)`인 그룹만 포함한다. 새 규칙 종류를 추가하면 `RuleGroupProfile`과 이 분석 계약을 함께 갱신한다.
- **연장 불가 기간 중 편집 차단은 `ManageGroupsUseCase`의 update 3종(`updateRule`/`updateWeekdayRules`/`updateSelection`)과 `deleteGroup`의 guard가 담당한다**(조용히 무시 패턴 — `updateName`은 집행 무관이라 의도적으로 제외). 그룹을 변경하는 새 UseCase 메서드를 추가하면 같은 `isStrictLockActive()` guard를 반드시 넣을 것. `activateStrictLock`은 **범위(`strictLockDayRange` 1...30) 검증**(프리셋 검증이 아니다 — 커스텀 기간이 정상 경로) + applied·유효 규칙만 + **연장만 허용(만료 축소 거부)** + 최초 `strictStartedAt` 유지. 칩 프리셋은 `strictLockDayPresets`(1/3/7)이고 시트 기본 선택은 `strictLockDefaultDays`(1 — **가장 짧은 프리셋이어야** 시트가 "1일 칩 선택 + 휠 접힘"으로 열린다, 2026-07-31 변경). 커스텀 칩을 눌렀을 때 휠이 잡는 시드는 별개 상수 `strictLockCustomSeedDays`(14)이고 이쪽은 반대로 **프리셋에 없어야** 커스텀 칩 선택 상태가 유지된다. `ExtendGroupUseCase`의 strict 판정은 원본 그룹(`shieldRepository.lockedGroups()`) 기준이다 — resolved 투영은 strict 필드가 스트립되므로 판정에 쓰지 말 것.
