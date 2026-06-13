# Data 레이어

Domain Repository 프로토콜의 구현체. Core 서비스 호출 + Core ↔ Domain 타입 매핑.
구성요소는 이 폴더를 직접 보면 된다.

## 코드만 봐선 모르는 것

- 구현은 `final class XxxRepositoryImpl: XxxRepository`.
- Core 서비스는 생성자 주입 또는 싱글톤으로 사용.
- **Core 타입 → Domain 타입 변환이 이 레이어의 책임**. extension 또는 private 함수로 처리.
  예: `ScreenTimeRepositoryImpl` 내부의 `ScreenTimeManager.ExtensionSource.domainType`.
- 상태 관리에 `@Observable` **사용 금지**(Presentation 패턴을 Data로 들이지 말 것).

레이어 의존 규칙·추가 패턴은 `docs/agent/architecture.md`.

## 주의사항 (작업 중 발견 시 누적)

- (작업 중 발견한 Data 함정을 한 줄씩 누적)
