# Working Rules

Read when: 작업 위험도, 검증 수준, 완료 보고 기준을 정해야 할 때.

Skip when: 이미 작고 명확한 문서/문구 수정이며 검증 기준이 자명할 때.

변경을 어느 정도 조심해서 다뤄야 하는지 판단하는 기준입니다.

## 기본 작업 흐름

1. `AGENTS.md`에서 작업 유형, 읽을 상세 문서, 검증 방식을 먼저 고정합니다.
2. 수정 전에 관련 코드 경로와 현재 구현 흐름을 읽습니다.
3. 위험도를 분류하고, high-risk 작업은 직렬로 처리합니다.
4. 목표를 만족하는 가장 작은 변경을 합니다.
5. 먼저 정한 테스트/시나리오로 실행 또는 확인합니다.
6. 변경 파일, 실행한 검증, 실행하지 못한 검증을 보고합니다.
7. 테스트 코드로 대체할 수 없는 실기기 확인 항목이 남으면 최종 보고에 사용자 체크리스트로 적습니다.

## 작업 유형

| 유형 | 예시 | 먼저 정할 검증 |
| --- | --- | --- |
| UI-only | SwiftUI 레이아웃, 문구, 색상 | acceptance criteria 먼저, HIG/iOS 26.0 적합성 확인, 가능하면 build 또는 preview 성격의 확인 |
| Shared state | `SharedStore`, 카운터, 통계 | unit test 또는 regression test 먼저 |
| Screen Time / Shield | `ScreenTimeManager`, DeviceActivity, Shield extension | 실기기 검증 시나리오 먼저, 가능한 순수 로직은 unit test |
| Ads | `RewardedAdService`, `AdMockView`, 보상 콜백 | reward/fallback 시나리오 먼저, 가능한 wrapper/helper는 unit test |
| Project config | `.xcodeproj`, SPM, entitlements, App Group | 설정 검증 시나리오 먼저, build와 target membership 검토 |
| Docs-only | Markdown guide, setup note | 링크/경로 일치, 중복 확인, `CLAUDE.md`만 편집 후 `scripts/sync-agent-docs.sh`로 `AGENTS.md` 동기화 |

## 검증 선택 규칙

- 순수 로직, 저장/조회, 날짜 key, 카운터, formatter/helper는 unit test 또는 regression test로 확인합니다.
- UI-only 변경은 acceptance criteria를 먼저 쓰고, 가능하면 build로 컴파일 회귀를 확인합니다. HIG/iOS 26.0 적합성, 기본 iOS 컴포넌트 우선 여부, 접근성/동적 글자 크기도 함께 봅니다.
- 날짜/시간, 선택, 설정, 확인 흐름은 `DatePicker`, `Picker`, `Form`, `confirmationDialog` 같은 의미에 맞는 시스템 컴포넌트를 먼저 검토합니다.
- 공용 가능성이 있는 UI는 `GoldTime/GoldTime/Presentation/Component/` 추출 여부를 판단합니다.
- 새 색상은 `AccentColor`를 제외하고 RGB literal 대신 Asset Color로 추가했는지 확인합니다.
- FamilyControls, DeviceActivity, ManagedSettings Shield, Shield extension, 알림 복귀는 수동/실기기 시나리오를 먼저 정합니다.
- Screen Time / Shield 런타임은 `xcodebuild test` 통과만으로 완료 검증처럼 말하지 않습니다. 실제 기기에서만 확인 가능한 항목은 완료 보고에 남깁니다.
- 문서, 단순 문구, 순수 시각 조정은 자동 테스트를 생략할 수 있지만 확인 기준은 먼저 정합니다.
- 기획이 모호한 작업은 `competitive-research.md` 확인 여부를 검증 기준에 포함합니다. 최신 리서치를 했다면 재사용 가치가 있는 관찰을 해당 문서에 추가했는지 확인합니다.
- 자세한 TDD 기준과 실기기 시나리오 템플릿은 `testing.md`를 따릅니다.

## 위험도

- Low: 독립적인 문서, 문구, 공유 상태를 건드리지 않는 단일 view.
- Medium: `SharedStore`를 읽는 UI, 광고 표시, 알림 문구, 테스트.
- High: `SharedStore`, `ScreenTimeManager`, extension, entitlements, target membership, `.xcodeproj`, package dependency.

High-risk 작업은 직렬로 처리하고 명시적인 검증 메모를 남깁니다.

## 가볍게 하지 말 것

- migration/reset 결정 없이 App Group key를 바꾸지 않습니다.
- project config 작업이 아닌데 `.xcodeproj`를 기계적으로 수정하지 않습니다.
- 시뮬레이터 런타임으로 Screen Time 동작이 검증됐다고 보지 않습니다.
- 자동 테스트로 확인하지 못한 FamilyControls, DeviceActivity callback, ManagedSettings Shield, Shield extension, AdMob reward 동작을 보고에서 누락하지 않습니다.
- 중앙화할 수 있는 상태 로직을 앱과 extension에 중복 구현하지 않습니다.
- build, signing, simulator, sandbox 실패를 숨기지 않습니다.
- 명시 요청 없이 사용자 변경을 되돌리지 않습니다.
- FamilyControls, DeviceActivity, ManagedSettings 등 Apple 프레임워크 관련 문제가 생기면 추측하지 말고 Apple 공식 문서(developer.apple.com)를 먼저 확인합니다.
- iOS 26.0+ UI와 SwiftUI 패턴은 HIG와 Apple 공식 문서를 우선하고, 기본 iOS 컴포넌트를 대체하는 커스텀 UI는 이유를 남깁니다.
- `DatePicker`가 맞는 날짜/시간 입력을 임의 버튼 묶음이나 별도 picker 조합으로 재구현하지 않습니다.
- RGB/hex literal을 새로 추가하지 않습니다. 필요한 색상은 Asset Color로 추가합니다.

## 검증 명령

빌드와 테스트는 `xcodebuild` CLI를 기본으로 사용합니다(2026-07-11 전환). Xcode MCP 툴은
CLI가 막히거나 IDE 상태(RenderPreview, 네비게이터 이슈 등)가 필요할 때만 fallback입니다.

### xcodebuild (레포 루트 기준, 전부 실제 검증된 명령)

- **빌드**:
  ```bash
  xcodebuild -project GoldTime/GoldTime.xcodeproj -scheme GoldTime \
    -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
  ```
  `-quiet`는 성공 시 출력이 거의 없다 — exit 0이면 성공.
- **전체 테스트**: 위 명령의 `build` → `test`. exit 0 = 전부 통과(실패 시에만 실패 목록 출력).
- **특정 테스트**: `test`에 `-only-testing:'GoldTimeTests/ViewModelTests/테스트이름()'` 추가.
  식별자는 `타겟/스위트/함수명()` — **괄호까지 포함**해야 매칭된다.
- **결과 수 확인**(아래 함정 때문에 특정 테스트 후엔 필수):
  ```bash
  RESULT=$(ls -td ~/Library/Developer/Xcode/DerivedData/GoldTime-*/Logs/Test/*.xcresult | head -1)
  xcrun xcresulttool get test-results summary --path "$RESULT"
  ```

### xcodebuild 함정 (실측)

- **`-only-testing` 식별자가 아무것도 매칭하지 못하면 0개 실행으로 `TEST SUCCEEDED`가 뜬다
  (거짓 성공)**. 괄호 누락이 흔한 원인. exit code만 믿지 말고 xcresult에서
  `totalTestCount`를 확인한다.
- destination의 name-only 지정은 **최신 런타임에 그 이름이 있어야** 잡힌다. 예: "iPhone 16
  Pro"는 이 맥에 iOS 18.0 런타임에만 있어 실패했다("Unable to find a device") → 최신 런타임에
  있는 이름(예: iPhone 17)을 쓰고, 모호하면 `-showdestinations`로 확인.
- 테스트 stdout에는 개별 테스트 라인이 나오지 않는다(Xcode 16+, `-quiet` 무관). `-quiet`면
  xcresult 경로 라인도 생략되니 DerivedData에서 최신 xcresult를 찾는다(위 명령).
- `xcodebuild test`는 시뮬레이터 앱 데이터를 초기화할 수 있다(TEST_HOST + 공유 App Group).
  실사용 기기와는 무관.

### Xcode MCP (fallback)

1. `mcp__xcode__XcodeListWindows`로 GoldTime 프로젝트의 `tabIdentifier` 확인 (예: `windowtab3`).
2. 빌드 `mcp__xcode__BuildProject`, 전체 테스트 `mcp__xcode__RunAllTests`, 특정 테스트
   `mcp__xcode__RunSomeTests`(`testIdentifier` 예:
   `ViewModelTests/statsViewModelTodayDeltaCorrectAcrossWeekBoundary()`), 로그
   `mcp__xcode__GetBuildLog`, 목록 `mcp__xcode__GetTestList`.
3. 연결 오류면 `/mcp`로 재연결. 그래도 실패하면 원인을 기록하고 xcodebuild로 돌아온다.

## 완료 보고

최종 보고에는 다음을 포함합니다.

- 무엇을 바꿨는지.
- 먼저 정한 검증 방식.
- 실행한 검증 명령 또는 수동 확인.
- 실행하지 못한 검증과 이유.
- 남은 실기기 확인 항목이 있으면 사용자가 바로 확인할 수 있는 체크리스트.
- 최신 경쟁/유사 앱 리서치를 했다면 `competitive-research.md`에 반영한 내용 또는 반영하지 않은 이유.
