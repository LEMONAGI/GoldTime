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

- (작업 중 발견한 Domain 함정을 한 줄씩 누적)
