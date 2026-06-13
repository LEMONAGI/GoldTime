# GoldTime Agent Guide

GoldTime은 스크린타임 한도를 넘기면 Shield 흐름과 보상형 광고 해제를 통해 사용 시간을
의식하게 만드는 iOS 앱입니다. 메인 SwiftUI 앱 1개 + Screen Time extension 3개,
Clean Architecture 5개 레이어(폴더링)로 구성됩니다.

이 파일은 항상 로드되는 **진입점**입니다. 세부 규칙은 여기 담지 않고, 작업 위치에 따라
자동으로 로드되는 nested 가이드와 "찾아 읽는 공통 문서"로 분리했습니다.
`AGENTS.md`는 이 파일의 사본입니다(편집은 `CLAUDE.md`만, 동기화는 `scripts/sync-agent-docs.sh`).

---

## 🚨 작업 전 반드시 알 것 (Non-negotiables)

1. **의존 방향은 단방향**: `App → Presentation → Domain ← Data → Core`.
   역방향 import 금지. **Domain/Data에서 `@Observable`·`@Published` 금지**. Presentation은
   UseCase만 의존하고 Core/Data를 직접 참조하지 않는다.
2. **공유 상태(`SharedStore`, App Group)는 하위 호환 우선**. key 이름·Codable 구조 변경은
   설치된 앱 상태 마이그레이션이다. 새 `ScreenTimeGroup` 필드는 custom Codable로 throw하지
   않게 디코딩한다(배열 전체 `try?` 디코딩 → 1개 실패가 전체 소실).
3. **Screen Time / Shield / FamilyControls / DeviceActivity / AdMob 실제 표시는 실기기 검증
   필수**. 시뮬레이터 build는 컴파일 회귀만 증명하지 런타임 동작을 증명하지 않는다.
4. **새 색상은 Asset Color**. RGB/hex literal과 `Color+Brand.swift` 같은 수동 색상 extension은
   금지(`AccentColor`는 `Color.accent` 자동 생성).
5. **`.xcodeproj`, entitlements, App Group, `SharedStore`, `ScreenTimeManager`, extension은
   위험도 High** → 직렬로 처리하고 검증 메모를 남긴다. 워크트리의 사용자 변경은 보존한다.
6. 브랜치 `Type/이슈`, 커밋 `[Type] 한글 설명`. **광고 관련 변경은 `[Ad]` 태그**.

---

## 📂 문서 자동 로딩 (컨텍스트 관리의 핵심)

레이어/타겟 폴더에 `CLAUDE.md`가 **co-locate** 되어 있다. 그 경로의 파일을 열면 해당
`CLAUDE.md`가 자동으로 함께 로드된다 → **필요한 문서만 정확히** 읽힌다.

```
CLAUDE.md                                        ← 항상 (이 파일)
GoldTime/GoldTime/App/CLAUDE.md                  ← DI 조립 규칙
GoldTime/GoldTime/Core/CLAUDE.md                 ← SharedStore/ScreenTime 함정 (High)
GoldTime/GoldTime/Domain/CLAUDE.md               ← import/UseCase/Repository 규칙
GoldTime/GoldTime/Data/CLAUDE.md                 ← Repository 구현/타입 매핑
GoldTime/GoldTime/Presentation/CLAUDE.md         ← ViewModel/컴포넌트/색상
GoldTime/DeviceActivityMonitorExtension/CLAUDE.md   ← 콜백/일일 리셋/시간대 (High)
GoldTime/ShieldConfigurationExtension/CLAUDE.md     ← Shield UI 읽기 계약 (High)
GoldTime/ShieldActionExtension/CLAUDE.md            ← Shield 액션 쓰기 계약 (High)
```

예: `Core/Persistence/SharedStore.swift`를 만지면 이 파일 + `Core/CLAUDE.md`가 함께 로드된다.
**→ 다른 레이어 문서를 일부러 찾아 읽지 말 것.** 작업 위치가 필요한 문서를 알아서 가져온다.
작업 중 함정을 발견하면 가장 가까운 `CLAUDE.md`의 "주의사항" 절에 누적한다(`/learn`).

### 찾아 읽는 공통 문서 (자동 로드 X)

| 문서 | 언제 |
|---|---|
| [docs/agent/architecture.md](docs/agent/architecture.md) | 레이어 의존 방향, 새 파일 배치, UseCase/Repository 추가 |
| [docs/agent/critical-flows.md](docs/agent/critical-flows.md) | Screen Time/Shield/광고/App Group 런타임 흐름 전체 |
| [docs/agent/testing.md](docs/agent/testing.md) | TDD, regression, 실기기 검증 시나리오 |
| [docs/agent/working-rules.md](docs/agent/working-rules.md) | 작업 유형, 위험도, 검증 명령(Xcode MCP) |
| [docs/agent/task-harness.md](docs/agent/task-harness.md) | 큰 작업 분해, step 상태, 병렬/직렬 판단 |
| [docs/agent/definition-of-done.md](docs/agent/definition-of-done.md) | **작업 종료 규칙** (완료 직전 자가 점검) |
| [docs/agent/decision-context.md](docs/agent/decision-context.md) | 제품 범위, 하지 않을 일, ADR |
| [docs/agent/product-context.md](docs/agent/product-context.md) | 문구, 톤앤매너, 화면 감정 |
| [docs/agent/ui-design-system.md](docs/agent/ui-design-system.md) | iOS UI/HIG, 공용 컴포넌트, Asset Color |
| [docs/agent/competitive-research.md](docs/agent/competitive-research.md) | 기획 모호성, 경쟁 앱 참고, GoldTime다움 |
| [docs/agent/app-icon-brief.md](docs/agent/app-icon-brief.md) | 앱 아이콘 시안/프롬프트 |
| [docs/agent/project-map.md](docs/agent/project-map.md) | 타겟/경로/entitlement/App Group 위치 |

기획이 모호하면 경쟁 앱을 그대로 따르지 말고 GoldTime의 비용감·마찰·Shield 선택 경험에 맞게
해석한다. 문서가 코드와 다르면 **코드가 진실** — 발견 즉시 가장 가까운 `CLAUDE.md`를 고친다.

---

## ✅ 작업 종료 규칙

완료를 보고하기 전에 [docs/agent/definition-of-done.md](docs/agent/definition-of-done.md)로
자가 점검한다. 핵심: 의존 방향/상태 규칙 위반 없음, 변경에 가장 가까운 `CLAUDE.md` 갱신,
정한 검증 실행, 실기기로만 확인 가능한 항목은 완료 보고에 사용자 체크리스트로 남김.

---

## 🛠 검증 명령

빌드/테스트는 **반드시 Xcode MCP 툴**을 쓴다(`xcodebuild` CLI는 fallback).
호출 전 `mcp__xcode__XcodeListWindows`로 `tabIdentifier`를 먼저 확인한다. 빌드
`BuildProject`, 전체 테스트 `RunAllTests`, 특정 테스트 `RunSomeTests`. 자세히는
[docs/agent/working-rules.md](docs/agent/working-rules.md)의 "검증 명령".
