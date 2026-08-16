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

- `AnalyticsRepositoryImpl`의 연장 불가 완료 pending은 앱 전용 `UserDefaults.standard`에 저장한다.
  시작·연장 때만 생성해 과거 만료 그룹을 소급 집계하지 않고, 같은 그룹 연장은 최종 만료로
  덮어쓴다. 완료 drain·권한 철회 discard 뒤 키를 비워 앱 재진입 중복을 막는다.
