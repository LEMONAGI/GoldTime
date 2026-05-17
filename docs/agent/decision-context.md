# Decision Context

Read when: 제품 범위, MVP 포함/제외, 구조적 방향, 오래 유지할 결정을 판단해야 할 때.

Skip when: 코드 위치만 찾거나, 문구만 바꾸거나, 이미 정해진 작은 구현을 수행할 때. 경쟁 앱 참고와 GoldTime다운 판단만 필요하면 `competitive-research.md`를 먼저 읽습니다.

## PRD 기준

GoldTime은 사용자가 스크린타임 한도를 넘긴 순간을 그냥 넘기지 않게 만드는 앱입니다. Shield, 짧은 연장, 보상형 광고 선택지를 통해 "계속 쓰는 행동"에 의식적인 비용을 붙입니다.

제품 카테고리는 일반적인 생산성 차단 앱보다 "무의식적 사용에 통행료를 붙이는 앱"에 가깝습니다. GoldTime은 앱 사용을 완전히 끊게 만들기보다, 한도 초과 뒤의 계속 쓰는 선택을 결제대 앞의 선택처럼 느끼게 만듭니다.

기획이 모호한 경우 경쟁 앱을 그대로 따라가지 말고 `competitive-research.md`의 "GoldTime다운 판단 기준"으로 해석합니다. 제품 범위 판단은 이 문서가 담당하고, 경쟁/유사 앱 패턴과 적용점은 `competitive-research.md`가 담당합니다.

핵심 루프:

1. 사용자가 앱 그룹과 일일 한도를 정합니다.
2. 한도에 닿으면 Shield가 사용 흐름을 끊습니다.
3. 사용자는 그만 쓰기, 제한된 1분 연장, 광고 보고 15분 연장 중 하나를 고릅니다.
4. GoldTime은 선택 결과를 기록하고 다음 선택을 더 의식적으로 만들 피드백을 보여줍니다.

타겟 사용자는 다음과 같습니다.

- iPhone 사용 시간을 줄이고 싶지만 완전 차단 앱은 부담스러운 사용자.
- SNS, 숏폼, 웹 탐색을 습관적으로 더 쓰는 사용자.
- 훈계보다 약간 냉소적인 장치가 더 잘 먹히는 사용자.
- 웰니스 앱의 응원 문구보다 짧고 건조한 마찰을 선호하는 사용자.

MVP 핵심 기능:

- FamilyControls 권한 요청과 차단 대상 선택.
- 일일 한도 기반 DeviceActivity 모니터링.
- 한도 도달 시 Shield 적용.
- 1분 연장, 광고 보상 해제, 참기 선택지.
- App Group 기반 상태 공유와 기본 대시보드 통계.

MVP 성공 기준:

- 사용자가 Shield를 만나고도 선택지를 바로 이해합니다.
- 사용자가 광고를 보지 않고 그만두는 순간을 승리처럼 인식합니다.
- 1분 연장과 광고 연장이 무제한 우회가 아니라 제한된 비용처럼 느껴집니다.
- 대시보드는 총 사용 시간보다 광고 회피, 참기 선택, 남은 1분, 추가 사용 시간, Shield hit 감소를 우선합니다.
- 앱은 유머가 있지만 사용자를 비난하거나 수치심을 주지 않습니다.

MVP에서 하지 않을 일:

- 부모 통제, 감시, 리포트 중심 기능.
- 계정, 서버 동기화, 소셜 기능.
- 정밀한 앱별 사용 분석이나 장기 리포트.
- 광고 수익 최적화 시스템.
- AI 코칭, 자동 행동 분석, 복잡한 추천.
- 완전한 차단 우회 방지 보장.
- 친구 랭킹, 공개 챌린지, 경쟁형 소셜 기능.
- 하드웨어/NFC 기반 물리적 잠금.

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
