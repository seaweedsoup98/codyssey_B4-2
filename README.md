# B4-2 | Linux 프로세스 장애 분석

Codyssey의 제공 프로그램 `agent-leak-app`에서 **메모리 증가·MemoryGuard 종료**, **CPU 부하·Watchdog 종료**, **멀티스레드 교착상태**를 관측하고, 환경변수 하나를 변경한 Before/After 실험으로 원인을 진단하는 미션이다. 보너스 스케줄링 추론은 제외했다.

## 제출물과 검증 상태

| 항목 | 상태 |
| --- | --- |
| 실행 환경 구성·관제·실험 스크립트 | 작성 및 **모의 프로세스에 대한 작동 검증 완료** |
| OOM 분석 GitHub Issue | [#1](https://github.com/seaweedsoup98/codyssey_B4-2/issues/1) — **실제 증거 수집 전** |
| CPU 분석 GitHub Issue | [#2](https://github.com/seaweedsoup98/codyssey_B4-2/issues/2) — **실제 증거 수집 전** |
| Deadlock 분석 GitHub Issue | [#3](https://github.com/seaweedsoup98/codyssey_B4-2/issues/3) — **실제 증거 수집 전** |

**제공된 `agent-app-leak.zip` 원본이 현재 없으므로 실제 바이너리의 장애 재현·Before/After 실측은 완료되지 않았다.** PDF 예시나 다른 저장소의 수치를 실측 결과로 사용하지 않는다. Issue 3건은 증거를 채울 수 있도록 준비된 분석 기록이며, 현재는 실측 대기 상태다.

## 실행 방법 (Linux, 일반 사용자)

미션 자료에서 **공식** `agent-app-leak.zip`을 받아 이 저장소 루트에 둔다. 격리된 Linux VM·컨테이너를 권장한다. 포트 `15034`를 외부에 공개하지 않는다. `unzip`, `procps`(`ps`, `top`), `iproute2`(`ss`), `util-linux`(`setsid`), `awk`가 필요하다.

```bash
bash scripts/setup.sh
source "$HOME/agent-leak-lab/agent.env"

# 각 장애 유형을 두 번씩 관찰한다. 120초는 최대 관측 시간이다.
for kind in oom cpu deadlock; do
  for stage in before after; do
    bash scripts/run_case.sh "$kind" "$stage" 120
  done
done
```

`AGENT_HOME=/절대/경로 bash scripts/setup.sh /절대/경로/agent-app-leak.zip`으로 위치를 지정할 수도 있다. 다음 실행에서도 `AGENT_HOME`을 같은 값으로 지정해야 한다. 실행 파일은 저장소가 아닌 `$AGENT_HOME/agent-leak-app`에 설치된다.

### 6가지 비교 조건

| 실험 | MEMORY_LIMIT(MB) | CPU_MAX_OCCUPY(%) | MULTI_THREAD_ENABLE |
| --- | ---: | ---: | --- |
| OOM Before | 256 | 40 | false |
| OOM After | 512 | 40 | false |
| CPU Before | 512 | 80 | false |
| CPU After | 512 | 40 | false |
| Deadlock Before | 512 | 40 | true |
| Deadlock After | 512 | 40 | false |

이 값은 실험 조건이며, **장애 발생을 보장하는 측정 결과가 아니다.** 앱이 재현되지 않거나 다른 종료 원인이 나타나면 Issue에 그대로 기록한다. `MEMORY_LIMIT`(50~512), `CPU_MAX_OCCUPY`(10~100)는 미션의 허용 범위 안에 있다.

### 관제 및 판정

실행마다 `evidence/<UTC시각>-<유형>-<before|after>/` 폴더가 생긴다.

- `settings.txt`: 설정, 바이너리 해시, 시작 시각
- `application.log`·`agent-logs/`: 앱 실행 로그
- `monitor.tsv`: PID별 구간 CPU와 RSS 메모리
- `processes.txt`: PID, PGID, 스레드 TID/WCHAN, TCP 포트 확인
- `result.txt`: 앱 종료(`app_exit`) 또는 관측 제한 종료(`observation_limit`)

`observation_limit`는 **실험기가 앱에 종료를 요청한 경우**다. 이때 `exit_code=143`이어도 Watchdog이 종료했다고 주장할 수 없다. CPU의 구간 사용률은 OS `/proc` 기준으로 측정하며 앱 로그의 내부 `Current Load`와 별도 지표다. 원본 실행 로그를 먼저 읽고 Issue의 4개 섹션에 실측값을 반영한다.

## 저장소 구성 및 학습 순서

1. [구현 해설](docs/IMPLEMENTATION.md) — 실행 흐름·파일 역할·상태 변화·수집값 계산
2. [핵심 개념](docs/CONCEPTS.md) — Linux 프로세스/스레드, RSS, CPU, Watchdog, Deadlock
3. [평가 대비](docs/REVIEW.md) — 예상 질문, 핵심 논리, 코드 근거
4. [Issues](https://github.com/seaweedsoup98/codyssey_B4-2/issues) — 장애 현상, 증거, 원인, 조치 및 검증

**주의:** 바이너리 디컴파일·역공학은 하지 않는다. 제공 ZIP/실행 파일과 실제 비밀 키를 Git에 커밋하지 않는다. `secret.key`는 미션이 지정한 테스트용 값만 생성한다.
