# Architecture

Read when: 새 파일을 어느 레이어에 둘지 모를 때, 레이어 간 의존성을 건드릴 때, UseCase / Repository / RepositoryImpl을 추가할 때.

Skip when: 수정 대상 파일과 레이어가 이미 명확할 때.

> **레이어별 세부 규칙은 이 문서에 없다.** 각 레이어/타겟 폴더의 nested `CLAUDE.md`가
> 그 폴더의 파일을 열 때 자동 로드되어 알려준다(import 예외, 상태 규칙, 허용 경계, 실측 함정).
> 이 문서는 자동 로딩이 못 주는 것 — **레이어 사이의 관계와 새 파일의 배치**만 다룬다.

---

## 레이어 구조

GoldTime 메인 앱은 5개 레이어로 구성됩니다. 물리 모듈 분리는 없고, 폴더링으로 레이어를 표현합니다.

```
GoldTime/GoldTime/
│
├── App/            진입점 (GoldTimeApp — 루트 ViewModel 소유)
├── Core/           Apple Framework 래퍼 — ScreenTime, Auth, Notification, Ads, Persistence
├── Domain/         순수 Swift — Model, Repository 프로토콜, UseCase, Policy
├── Data/           Repository 구현체 (Core → Domain 매핑)
└── Presentation/   ViewModel + View (MVVM, @Observable)
```

### 의존 방향

```
Presentation ──→ Domain ←── Data ──→ Core
     App ──→ Presentation (진입점 — 루트 ViewModel 생성·소유)
```

- **Domain**은 아무것도 의존하지 않습니다(파일별 import 예외와 `ScreenTimeGroup` typealias
  유지 결정은 `Domain/CLAUDE.md`).
- **Core**는 Apple Framework만 의존합니다. **집행 비즈니스 로직(잠금·모니터링·리셋)의 실질
  위치는 Core(`SharedStore`/`ScreenTimeManager`)입니다** — extension 타겟과 파일 단위로
  공유해야 해서 static 기반이며, 이는 의도된 구조입니다(`decision-context.md` ADR).
- **Data**는 Domain 프로토콜 + Core 서비스를 의존합니다. RepositoryImpl은 Core로의 얇은
  pass-through가 정상입니다(로직을 여기 늘리지 않습니다).
- **Presentation**은 Domain UseCase / Repository 프로토콜 의존이 기본입니다. Core 직접 참조는
  `Presentation/CLAUDE.md`의 허용 경계(값 읽기·설정 키·UI 부수효과) 안에서만.
- **App**은 루트 ViewModel을 생성·소유만 합니다. 중앙 DI 컨테이너는 없습니다.

**Domain/Data에서 `@Observable`·`@Published`는 금지**입니다(Core 서비스는 예외적으로 허용).

---

## 새 파일을 어느 레이어에 둘지

| 추가할 것 | 레이어 | 경로 예시 |
|---|---|---|
| Apple framework 서비스 래퍼 (신규) | Core | `Core/{영역}/XxxService.swift` |
| 비즈니스 개체 타입 (struct/typealias) | Domain/Model | `Domain/Model/Xxx.swift` |
| 데이터 접근 계약 (protocol) | Domain/Repository | `Domain/Repository/XxxRepository.swift` |
| 비즈니스 로직 흐름 | Domain/UseCase | `Domain/UseCase/XxxUseCase.swift` |
| 비즈니스 규칙 (순수 판단 함수) | Domain/Policy | `Domain/Policy/XxxPolicy.swift` |
| Repository 구현체 | Data | `Data/XxxRepositoryImpl.swift` |
| 화면 상태 + 인터랙션 | Presentation | `Presentation/{화면}/XxxViewModel.swift` |
| SwiftUI 화면 | Presentation | `Presentation/{화면}/XxxView.swift` |
| 새 UseCase 배선 | Presentation | ViewModel 생성자에 `? = nil` 파라미터 추가 |

**extension에서도 필요한 판단 로직은 `Domain/Policy`로 뺍니다** — Policy는 extension 타겟
멤버십에 추가해 공유하는 것이 기본 패턴입니다(`decision-context.md` ADR).

---

## Extension 타겟 구조

메인 앱 외 세 개의 Screen Time Extension 타겟이 있습니다. 각 타겟의 계약과 함정은 그 폴더의
`CLAUDE.md`에 있습니다.

| 타겟 폴더 | 역할 |
|---|---|
| `DeviceActivityMonitorExtension/` | DeviceActivity interval/threshold callback에서 Shield 적용·해제, 일일 상태 정리 |
| `ShieldConfigurationExtension/` | 시스템 Shield 화면 문구·버튼 구성 (읽기 전용) |
| `ShieldActionExtension/` | Shield 버튼 액션 처리, 앱 복귀 요청 기록 (`SharedStore` 미링크 — 키 자체 복제) |

Extension은 메인 앱 API에 직접 의존하지 않습니다. `SharedStore`(App Group UserDefaults)와
알림으로만 상태를 주고받습니다. **App Group key와 Codable 저장 구조의 하위 호환은 필수**입니다.

---

## UseCase / Repository 추가 패턴

1. **Domain/Repository**에 protocol 추가
2. **Domain/UseCase**에 UseCase class 추가 (Repository를 생성자 주입)
3. **Data**에 RepositoryImpl 추가 (Core 서비스 호출 + 타입 매핑)
4. **Presentation** ViewModel 생성자에 `XxxUseCase? = nil` 파라미터 추가 — nil이면 내부에서
   `XxxRepositoryImpl()`로 기본 조립(기존 no-arg 호출부·테스트가 안 깨진다), 테스트는 Fake 주입

## DI 흐름 요약

```
GoldTimeApp                              ← 루트 ViewModel @State 소유
  └─ ContentViewModel()                  ← no-arg 생성 (프로덕션 경로)
       └─ init(manageGroupsUseCase: ManageGroupsUseCase? = nil, ...)
            └─ nil이면 내부에서 기본 조립:
                 ManageGroupsUseCase(
                   groupRepository: GroupRepositoryImpl(),        ← Core/SharedStore 참조
                   screenTimeRepository: ScreenTimeRepositoryImpl() ← Core/ScreenTimeManager 참조
                 )

GoldTimeTests                            ← 테스트 경로
  └─ ContentViewModel(manageGroupsUseCase: ManageGroupsUseCase(
       groupRepository: FakeGroupRepository(), ...))              ← Fake 명시 주입
```

중앙 DI 컨테이너는 없습니다(과거 `AppDIContainer`는 dead code라 2026-07 삭제, 재도입 금지).
ViewModel 생성자의 `? = nil` 기본값이 프로덕션 조립이고, 테스트만 명시 주입합니다.
