# Domain 레이어 — 가장 엄격

순수 Swift. Model, Repository 프로토콜, UseCase, Policy. 아무 레이어도 의존하지 않는다.
구성요소는 하위 폴더를 직접 보면 된다.

## import 규칙 (코드만 봐선 모르는 것)

- import은 **`Foundation`만**.
- `ManagedSettings`는 `Domain/Repository/ShieldRepository.swift`에서만 예외 허용.
- `FamilyControls`는 `typealias` 선언 파일에서만 허용. 나머지 Domain 파일에서 직접 import 금지.
- `ScreenTimeManager`, `AuthorizationService` 등 Core 서비스 **직접 참조 금지**.

## 패턴

- Repository는 **프로토콜만** 선언. 구현체(`Impl`)는 Domain에 없다(Data에 있다).
- UseCase는 `final class`, Repository를 생성자에서 `any RepositoryProtocol`로 주입.
- 상태 관리에 `@Observable`·`@Published` **사용 금지**(순수 값/참조 타입).

## 기술 부채 (의도된 예외 — 향후 분리 예정)

- `Domain/Model/ScreenTimeGroup.swift`가 `typealias ScreenTimeGroup = SharedStore.ScreenTimeGroup`
  으로 SharedStore 타입을 재노출 중. (Domain 독립 타입으로 분리 예정)
- `ManageGroupsUseCase`가 `SharedStore.maxGroupCount` 상수를 직접 참조 중.

## 비즈니스 규칙

- **유효한 그룹** = 적용됨(`isApplied`) + 앱/웹사이트 1개 이상 + 규칙 유효(일일 한도 0분 이상,
  시간대는 TimeWindowPolicy 통과) + 앱+웹사이트 합산 그룹당 제한 이내. draft·미완성 그룹은
  저장하되 모니터링에서 제외.
- 시간대(TimeWindow)는 **그룹당 최대 3개, 15분 이상, 자정 넘김 금지**.

레이어 의존 다이어그램·새 파일 배치는 `docs/agent/architecture.md`.

## 주의사항 (작업 중 발견 시 누적)

- (작업 중 발견한 Domain 함정을 한 줄씩 누적)
