# Decision Context

Read when: 제품 범위, MVP 포함/제외, 구조적 방향, 오래 유지할 결정을 판단해야 할 때.

Skip when: 코드 위치만 찾거나, 문구만 바꾸거나, 이미 정해진 작은 구현을 수행할 때.

## PRD 기준

GoldTime은 사용자가 스크린타임 한도를 넘긴 순간을 그냥 넘기지 않게 만드는 앱입니다. Shield, 짧은 연장, 보상형 광고 선택지를 통해 "계속 쓰는 행동"에 의식적인 비용을 붙입니다.

타겟 사용자는 다음과 같습니다.

- iPhone 사용 시간을 줄이고 싶지만 완전 차단 앱은 부담스러운 사용자.
- SNS, 숏폼, 웹 탐색을 습관적으로 더 쓰는 사용자.
- 훈계보다 약간 냉소적인 장치가 더 잘 먹히는 사용자.

MVP 핵심 기능:

- FamilyControls 권한 요청과 차단 대상 선택.
- 일일 한도 기반 DeviceActivity 모니터링.
- 한도 도달 시 Shield 적용.
- 1분 연장, 광고 보상 해제, 참기 선택지.
- App Group 기반 상태 공유와 기본 대시보드 통계.

MVP에서 하지 않을 일:

- 부모 통제, 감시, 리포트 중심 기능.
- 계정, 서버 동기화, 소셜 기능.
- 정밀한 앱별 사용 분석이나 장기 리포트.
- 광고 수익 최적화 시스템.
- AI 코칭, 자동 행동 분석, 복잡한 추천.
- 완전한 차단 우회 방지 보장.

## Architecture 기준

GoldTime은 메인 SwiftUI 앱과 세 개의 Screen Time extension으로 나뉩니다.

- Main app: 권한, 설정, 대시보드, 해제 선택지, 광고 표시를 담당합니다.
- DeviceActivity extension: interval / threshold callback에서 Shield 적용과 일일 상태 정리를 담당합니다.
- ShieldConfiguration extension: 시스템 Shield 화면의 문구와 버튼 구성을 담당합니다.
- ShieldAction extension: Shield 버튼 액션을 처리하고 앱 복귀 요청을 기록합니다.
- `SharedStore`: App Group UserDefaults wrapper로 메인 앱과 extension 사이의 최소 공유 상태를 담당합니다.

기본 방향:

- View는 사용자 입력과 표시를 담당하고, Screen Time 판단은 service/shared state 쪽으로 보냅니다.
- Apple framework 호출부는 얇게 유지하고, 테스트 가능한 판단 로직은 분리합니다.
- Extension은 앱 전용 API에 의존하지 않고 App Group 상태와 알림을 통해 메인 앱과 이어집니다.
- App Group key와 Codable 저장 구조는 설치된 앱 상태에 영향을 주므로 하위 호환을 우선합니다.

## ADR 기준

현재 유지할 결정:

- 루트 agent 문서는 짧은 라우터로 유지하고, 상세 문서는 필요한 것만 읽습니다.
- 자동화 하네스보다 step card 기반의 얇은 작업 규약을 사용합니다.
- MVP에서는 작동하는 Screen Time / Shield 흐름을 제품 확장보다 우선합니다.
- Screen Time / Shield 영역은 unit test보다 실기기 검증 시나리오를 먼저 고정합니다.
- 공유 상태는 MVP에서 App Group UserDefaults를 사용합니다.
- 외부 의존성은 실제 문제를 줄일 때만 추가합니다.

주요 트레이드오프:

- App Group UserDefaults는 단순하지만 schema migration과 동시 쓰기에 약합니다.
- Apple Screen Time framework는 제품 핵심을 가능하게 하지만 실기기 검증 의존이 큽니다.
- 얇은 문서 구조는 컨텍스트를 아끼지만, 문서 선택 규칙을 지키지 않으면 효과가 사라집니다.
