# Working Rules

Read when: 작업 위험도를 판단하거나, 빌드/테스트/실기기 로그 수집 명령이 필요할 때.

Skip when: 이미 작고 명확한 문서/문구 수정이며 검증 기준이 자명할 때.

이 문서의 핵심은 아래 **"검증 명령"** 절이다 — 전부 이 맥에서 실제로 실행해 확인한 명령과
그 함정이다. 작업 종료 기준은 `definition-of-done.md`, 테스트 판단 기준은 `testing.md`.

## 위험도

- **Low**: 독립적인 문서, 문구, 공유 상태를 건드리지 않는 단일 view.
- **Medium**: `SharedStore`를 읽는 UI, 광고 표시, 알림 문구, 테스트.
- **High**: `SharedStore`, `ScreenTimeManager`, extension, entitlements, target membership,
  `.xcodeproj`, package dependency.

High-risk 작업은 **직렬로 처리**하고 명시적인 검증 메모를 남깁니다.

## 검증 선택 (GoldTime 고유 기준)

- 순수 로직·저장/조회·날짜 key·카운터·formatter는 unit/regression test. 실기기에서 발견한
  버그도 가능한 부분을 순수 로직으로 환원해 테스트로 남깁니다.
- **Screen Time / Shield / FamilyControls / AdMob 실제 표시는 `xcodebuild test` 통과만으로
  완료 처리하지 않습니다.** 실기기에서만 확인 가능한 항목은 완료 보고에 체크리스트로 남깁니다.
- 새 색상은 `AccentColor` 제외하고 RGB/hex literal 대신 Asset Color.
- 날짜/시간·선택·설정·확인 흐름은 `DatePicker`/`Picker`/`Form`/`confirmationDialog` 같은
  의미에 맞는 시스템 컴포넌트를 먼저 검토합니다(`ui-design-system.md`).
- 기획이 모호하면 `competitive-research.md`를 확인하고, 재사용 가치가 있는 관찰은 그 문서에
  추가합니다.
- 문서 수정은 `CLAUDE.md`만 편집하고 `scripts/sync-agent-docs.sh`로 `AGENTS.md`를 동기화합니다.

## 가볍게 하지 말 것

- migration/reset 결정 없이 App Group key를 바꾸지 않습니다.
- project config 작업이 아닌데 `.xcodeproj`를 기계적으로 수정하지 않습니다.
- 시뮬레이터 런타임으로 Screen Time 동작이 검증됐다고 보지 않습니다.
- 중앙화할 수 있는 상태 로직을 앱과 extension에 중복 구현하지 않습니다.
- FamilyControls, DeviceActivity, ManagedSettings 문제는 추측하지 말고 Apple 공식 문서
  (developer.apple.com)를 먼저 확인합니다. iOS 26.0+ UI는 HIG를 우선하고, 기본 컴포넌트를
  대체하는 커스텀 UI는 이유를 남깁니다.

## 검증 명령

빌드와 테스트는 `xcodebuild` CLI를 기본으로 사용합니다(2026-07-11 전환). Xcode MCP 툴은
CLI가 막히거나 IDE 상태(RenderPreview, 네비게이터 이슈 등)가 필요할 때만 fallback입니다.

### xcodebuild (레포 루트 기준, 전부 실제 검증된 명령)

- **빌드**:
  ```bash
  xcodebuild -project GoldTime/GoldTime.xcodeproj -scheme GoldTime \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build
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
  Pro"는 이 맥에 iOS 18.0 런타임에만 있어 실패했다("Unable to find a device"). **설치돼 있지 않은
  이름도 같은 실패**를 낸다 — 2026-08-05 실측 기준 이 맥에는 "iPhone 17"이 없고 17 Pro/17e/Air만
  있다. 실제 설치 목록은 `xcrun simctl list devices available`(또는 `-showdestinations`)로 확인.
- 테스트 stdout에는 개별 테스트 라인이 나오지 않는다(Xcode 16+, `-quiet` 무관). `-quiet`면
  xcresult 경로 라인도 생략되니 DerivedData에서 최신 xcresult를 찾는다(위 명령).
- `xcodebuild test`는 시뮬레이터 앱 데이터를 초기화할 수 있다(TEST_HOST + 공유 App Group).
  실사용 기기와는 무관.
- **`git worktree`로 만든 트리는 Firebase 빌드가 깨진다**(`Could not get GOOGLE_APP_ID in
  Google Services file from build environment`). `GoogleService-Info.plist`가 `.gitignore`
  대상이고 `GoldTime/GoldTime/Resources/`에는 그 파일 **하나뿐**이라, git 입장에선 폴더 자체가
  없어 체크아웃되지 않는다. 워크트리를 만들 때마다 재발 → 메인 트리에서 복사한다:
  `mkdir -p <worktree>/GoldTime/GoldTime/Resources && cp GoldTime/GoldTime/Resources/GoogleService-Info.plist <worktree>/GoldTime/GoldTime/Resources/`.
  프로젝트가 `PBXFileSystemSynchronizedRootGroup`(Xcode 16 폴더 동기화)이라 파일만 놓으면
  타겟에 자동 포함된다(pbxproj 수정 불필요).

### 실기기 OSLog 수집 (실측)

extension은 별도 프로세스라 Xcode 콘솔에 안 잡힌다 → 자정 재무장·백그라운드 tick 같은 "사람이
안 볼 때 일어나는 일"의 유일한 증거는 기기 OSLog다(GTLog, `subsystem == "com.nagi.GoldTime"`).
로그는 앱 종료·재부팅 후에도 남으므로 사후 수집이 되지만, **GTLog는 오래 보존되지 않는다**
(`Df` = Debug 레벨). 자정 로그를 13시간 뒤 오후에 수집한 실측(2026-07-30)에서 같은 시각 Apple
프레임워크 로그 75줄은 남았는데 **GTLog는 2줄만** 남아 콜백 진입 로그(`▶︎ intervalDidStart`)
까지 유실됐다 — `--last`를 늘려도 복구되지 않는다(수집 창의 문제가 아니라 보존의 문제).

- **자정 판정이 목적이면 자정 직후 `00:05~00:15`에 `--last 30m`으로 수집한다**(최선). 로그가
  신선해 유실이 없고 파싱도 가볍다. **00:00 정각은 이르다** — iOS가 하트비트
  `intervalDidStart`를 자정보다 수 분 늦게 발화시킨 실측이 있다(00:02:50,
  `DeviceActivityMonitorExtension/CLAUDE.md`). 차선은 아침 일찍이고, 오후 수집은 GTLog 판정을
  포기하는 것과 같다.

- **수집은 사용자가 별도 터미널에서** 실행해야 한다: `sudo log collect --device --last 30m
  --output /tmp/x.logarchive`. Claude Code의 `!` 프리픽스는 **tty가 없어 sudo 비밀번호를 못
  받는다**(`a terminal is required to read the password`). 아카이브만 만들어지면 파싱은
  sudo 없이 에이전트가 한다.
- **조회는 반드시 `/usr/bin/log` 절대경로**. zsh에는 `log` **builtin**이 있어 `/usr/bin/log`를
  가린다 → `(eval):log:1: too many arguments`. `2>/dev/null`을 붙여두면 이 에러가 숨어
  **조용히 0줄**이 나와 "로그가 안 남았다"고 오판하기 쉽다.
  `/usr/bin/log show /tmp/x.logarchive --info --debug --predicate 'subsystem == "com.nagi.GoldTime"' --style compact`
  (GTLog `notice`는 `Df`로 찍히므로 `--info --debug` 필수).
- 디버그 빌드에서만 나온다. 검증 중에는 앱을 삭제·재설치하지 말 것(판정 대상 바이너리 고정).

### Xcode MCP (fallback)

1. `mcp__xcode__XcodeListWindows`로 GoldTime 프로젝트의 `tabIdentifier` 확인 (예: `windowtab3`).
2. 빌드 `mcp__xcode__BuildProject`, 전체 테스트 `mcp__xcode__RunAllTests`, 특정 테스트
   `mcp__xcode__RunSomeTests`(`testIdentifier` 예:
   `ViewModelTests/statsViewModelTodayDeltaCorrectAcrossWeekBoundary()`), 로그
   `mcp__xcode__GetBuildLog`, 목록 `mcp__xcode__GetTestList`.
3. 연결 오류면 `/mcp`로 재연결. 그래도 실패하면 원인을 기록하고 xcodebuild로 돌아온다.
