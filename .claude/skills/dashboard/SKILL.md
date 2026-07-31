---
name: dashboard
description: GoldTime 운영 대시보드(별도 프로젝트 goldtime-dashboard, Next.js 로컬 dev 서버)를 켜고 4개 데이터 소스(BigQuery·GA4·App Store Connect·AdMob) 연결 상태까지 확인해 보고한다. "대시보드 켜줘", "대시보드 다시 켜줘", "운영 지표 좀 보자", "DAU/수익/퍼널 확인하자", "리텐션 보고 싶어", "/dashboard" 처럼 **운영 수치를 보려는 낌새가 있으면 적극적으로 사용**한다. 서버를 끄거나 상태를 확인해 달라는 요청("대시보드 꺼줘", "아직 떠 있어?")에도 쓴다.
---

GoldTime 운영 대시보드를 **켜는 것**이 목적이 아니라, **사용자가 브라우저에서 바로 수치를
볼 수 있는 상태로 만들어 주는 것**이 목적이다. 그래서 서버만 띄우고 끝내지 말고, 데이터
소스가 실제로 붙었는지까지 확인해서 보고한다 — 소스가 끊긴 채 화면만 열리면 값이 0이나
빈칸으로 보여서 사용자가 "왜 아무것도 안 나오지?"로 시간을 쓰게 된다.

**프로젝트 위치**: `/Users/yunhaklee/Github/My/goldtime-dashboard` (iOS 레포와 형제,
별도 git repo). 실행은 `npm run dev`(Next.js), 호스팅 비용 0의 로컬 전용이다.

## 1. 이미 떠 있는지 먼저 본다

중복 실행은 포트만 하나 더 잡아먹고 사용자를 혼란스럽게 한다. 켜기 전에 확인한다:

```bash
curl -s --max-time 10 http://localhost:3000/api/health
```

- **대시보드 응답이 오면**(JSON에 `sources` 배열) 이미 떠 있는 것이다. 새로 켜지 말고
  "이미 떠 있다"고 알린 뒤 3단계(상태 보고)로 바로 간다.
- 응답이 없으면 2단계로 간다. Next는 포트가 차 있으면 자동으로 3001 등으로 올라가므로
  **URL은 추측하지 말고 실행 로그에서 읽는다**.

**살아있음 판정은 위 health 응답으로만 한다.** `lsof -ti:3000`은 서버뿐 아니라 **접속 중인
브라우저의 연결 프로세스까지** 잡는다(실측: WebKit Networking XPC가 나옴). 그 PID를 dev
서버로 착각하고 죽이면 엉뚱한 프로세스를 죽인다.

## 2. 켠다 (백그라운드)

dev 서버는 계속 떠 있어야 하므로 반드시 백그라운드로 실행한다(포그라운드로 돌리면 세션이
묶인다). `run_in_background: true`로:

```bash
cd /Users/yunhaklee/Github/My/goldtime-dashboard && npm run dev 2>&1
```

출력 파일을 읽어 `- Local: http://localhost:PORT`와 `✓ Ready`를 확인한다. **이 줄에 적힌
포트가 진짜 포트다.** 몇 초면 뜨지만 안 뜨면 출력 파일을 다시 읽어 원인을 본다(포트 충돌,
의존성 누락 등).

`.env.local`이 없으면 각 소스가 `not_configured`로 나온다(크래시는 안 남). 이 경우 값이
안 보이는 게 정상이므로 사용자에게 그렇게 알린다.

## 3. 데이터 소스 상태 확인 → 보고

```bash
curl -s --max-time 90 http://localhost:PORT/api/health
```

첫 호출은 라우트 컴파일 때문에 수십 초 걸릴 수 있다(타임아웃을 넉넉히). 응답의
`allOk`와 `sources[]`를 그대로 표로 보고한다:

| 소스 | 정상일 때 detail |
|---|---|
| BigQuery (Firebase export) | `dataset=analytics_...` |
| GA4 Data API | `property=...` |
| App Store Connect | JWT 인증 성공 |
| AdMob API | `account=pub-...` |

보고에 반드시 포함할 것:
- **접속 URL**(실제 포트)과 화면 목록: `/` 홈(DAU·다운로드·광고수익·Shield/Reward/Unlock),
  `/funnel` 퍼널, `/acquisition` 노출 분해, `/release` 릴리즈
- 실패한 소스가 있으면 어느 것이 왜 실패했는지. AdMob이 실패하면 OAuth 동의 계정이
  **nagi.appstudio@gmail.com**(개인 계정 아님)이라는 점이 흔한 원인 단서다.

## 4. 날짜 오해를 먼저 차단한다

이 대시보드에서 반복적으로 생기는 오해가 하나 있다. Firebase BigQuery 일일 export는 D일
테이블을 **D+1 아침 08:25~09:00 KST**에 만든다(스트리밍 export 없음). 그래서 화면 숫자는
"오늘"이 아니라 **실재하는 최신 확정일** 기준이다.

즉 **밤에 켜면 어제 값, 아침 8시 반 이전에 켜면 그저께 값**이 보이는 게 정상이다. 사용자가
"오늘 수치가 왜 이래?"로 헤매지 않게, 보고할 때 이 점을 한 줄 덧붙인다. (코드도 이미
`latestEventsDay()`로 최신 확정일을 쓰고 화면에 그 날짜를 표기한다.)

## 5. 끄기

"대시보드 꺼줘" 요청이면 백그라운드 작업을 정리한다. 이 세션에서 띄운 작업이면 그 작업을
중지하고, 아니면 포트를 점유한 PID를 확인해 사용자에게 알린 뒤 정리한다 — 확인 없이 남의
프로세스를 죽이지 않는다.

## 주의사항 (작업 중 발견 시 누적)

- 대시보드 코드를 고칠 일이 생기면 그 레포의 `AGENTS.md`(=`CLAUDE.md`)를 따른다. 이 스킬은
  **실행·상태 확인 전용**이다.
- ad-hoc 분석은 대시보드에 기능을 붙이기 전에 BigQuery 직접 질의로 먼저 답을 낸다
  (API 비용 0, 화면 추가보다 빠르다).
