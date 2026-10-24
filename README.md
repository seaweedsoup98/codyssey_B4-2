# B4-2 | Linux 프로세스 장애 분석

Codyssey 제공 `agent-leak-app`을 Linux에서 실행해 **메모리 보호 종료, CPU 보호 종료, 스레드 교착상태**를 직접 관측하고 환경변수 변경 전후를 비교한 실습이다. 바이너리를 수정·디컴파일하지 않았다. 보너스 과제는 제외했다.

## 실측 결과 (2026-10-24, UTC)

공식 제공 `agent-app-leak.zip`의 **x86-64 바이너리**를 일반 사용자로 실행했다. 부팅 검사 6개 모두 통과했고, 포트 `15034`에 바인딩했다. 3개 유형 각각 Before/After **총 6회 실행**했으며, 원본 로그와 `/proc` 측정을 [`evidence/`](evidence/)에 보존했다.

| 유형 | Before | After (변경한 변수만 다름) | 판정 |
| --- | --- | --- | --- |
| [OOM](https://github.com/seaweedsoup98/codyssey_B4-2/issues/1) | `MEMORY_LIMIT=256`: **33초** 후 MemoryGuard 종료, Heap **275MB**, RSS **266.22MiB** | `MEMORY_LIMIT=512`: **50초 관찰** 동안 생존, Heap **400MB**, RSS **416.46MiB** | 임계치 상향으로 생존 연장. 메모리 증가 자체는 지속 |
| [CPU](https://github.com/seaweedsoup98/codyssey_B4-2/issues/2) | `CPU_MAX_OCCUPY=80`: **34초** 후 내부 부하 **52.07%**에서 임계치 위반·SIGTERM 관련 종료 | `CPU_MAX_OCCUPY=40`: **50초 관찰** 동안 보호 종료 없음, 내부 부하 냉각 반복 | 내부 보호 종료 회피. **실제 OS CPU 폭주는 입증되지 않음** |
| [Deadlock](https://github.com/seaweedsoup98/codyssey_B4-2/issues/3) | `MULTI_THREAD_ENABLE=true`: 서로의 락을 기다리는 로그·스레드 정체, **40초 관찰** | `MULTI_THREAD_ENABLE=false`: `All tasks completed` 기록, **50초 관찰** | 순환 대기 회피, 정상 작업 완료 |

- 시간은 `settings.txt`의 시작·`result.txt`의 종료 시각을 기준으로 한 근삿값이다. Before OOM 33초, CPU 34초는 앱 자체 종료(`reason=app_exit`), 나머지는 실험기가 지정 시간에 종료(`reason=observation_limit`)했다. 실제 종료 기록 시각은 정리 작업 때문에 관찰 제한보다 1~2초 늦을 수 있다.
- CPU Before의 Linux 프로세스별 구간 CPU 최대치는 **5.94%**(작업 PID 최대 **3.96%**)였다. 앱 로그의 `Current Load: 52.07%`는 **Linux 측정 CPU 사용률로 해석할 수 없다**. 요청 응답 지연(latency)도 별도 측정하지 않았다.
- 세 유형 간 간섭을 줄이도록 비교 쌍마다 **변수 하나만 변경**했다. 동일 바이너리 SHA-256: `7e0a19cfa80ece6b547a5008273661f0d4d71e526e96b51e0d0f341dd1bb3e40`.

## 실험 재현 (Linux)

실험은 외부 포트가 공개되지 않는 **격리된 Linux VM/컨테이너**에서 실행한다. root가 아닌 일반 사용자와 `unzip`, `procps`(`ps`, `top`), `iproute2`(`ss`), `util-linux`(`setsid`), `awk` 등이 필요하다.

1. Codyssey에서 받은 **원본** `agent-app-leak.zip`을 저장소 최상위 경로에 둔다. 배포 바이너리는 이 저장소에 커밋하지 않는다.
2. 다음 명령을 실행한다.

```bash
bash scripts/setup.sh
source "$HOME/agent-leak-lab/agent.env"

for kind in oom cpu deadlock; do
  for stage in before after; do
    bash scripts/run_case.sh "$kind" "$stage" 50
  done
done
```

`AGENT_HOME=/절대/경로 bash scripts/setup.sh /ZIP/절대/경로`로 위치를 바꿀 수 있다. 설정 로딩은 해당 `AGENT_HOME/agent.env`에서 해야 한다. 실험 기간 기본값도 **50초**다. 특히 CPU·OOM의 After를 필요 이상 오래 실행하면 다른 장애(메모리 보호 종료)가 섞일 수 있다.

### 변수 통제 표

| 실행 | MEMORY_LIMIT(MB) | CPU_MAX_OCCUPY(%) | MULTI_THREAD_ENABLE |
| --- | ---: | ---: | --- |
| OOM Before | 256 | 40 | false |
| OOM After | 512 | 40 | false |
| CPU Before | 512 | 80 | false |
| CPU After | 512 | 40 | false |
| Deadlock Before | 512 | 40 | true |
| Deadlock After | 512 | 40 | false |

실행 시 **각 실험은 `evidence/<UTC시각>-<유형>-<전후>/`**에 별도로 기록된다. 제출된 6회 원본 로그는 읽기 쉬운 고정 경로인 `evidence/<유형>-<전후>/`에 복사해 두었다.

## 소스 및 증거 파일

| 위치 | 기능 |
| --- | --- |
| [`scripts/setup.sh`](scripts/setup.sh) | ZIP 아키텍처 선택, 파일·환경변수·테스트 키 준비 |
| [`scripts/run_case.sh`](scripts/run_case.sh) | 6개 실험 조건 선택, 프로세스 시작·종료, 증거 수집 |
| [`scripts/monitor.sh`](scripts/monitor.sh) | PGID에 속한 실제 PID별 1초 간격 CPU·RSS 기록 |
| [`evidence/`](evidence/) | 앱 로그, CPU/RSS 원본 TSV, `ps`/스레드 상태, 실행 설정·결과 |

실험별 원본 파일은 `settings.txt`(변수·시작 시각·해시), `application.log`(표준 출력/에러), `agent-logs/`(앱 자체 로그), `monitor.tsv`(PID별 CPU/RSS), `processes.txt`(PID/TID·WCHAN·포트), `result.txt`(종료 이유·종료 시각)다. `observation_limit`와 종료 코드 `143`을 **Watchdog 종료로 혼동하면 안 된다**.

## 학습·평가 자료

1. [핵심 개념](docs/CONCEPTS.md): 프로세스/PID·RSS·CPU·Watchdog·Deadlock의 기본 원리
2. [구현 해설](docs/IMPLEMENTATION.md): `setup` → `run_case` → `monitor`의 코드 흐름
3. [평가 대비](docs/REVIEW.md): 원본 로그에 근거한 예상 질문과 답변
4. [GitHub Issues](https://github.com/seaweedsoup98/codyssey_B4-2/issues): 관측 현상·증거·원인·임시 조치·비교 결과

**보안/범위:** 바이너리의 디컴파일·역공학 금지. ZIP/바이너리와 실제 비밀 키는 GitHub에 포함하지 않는다. 미션이 지정한 `agent_api_key_test`는 별도 로컬 `secret.key`로만 생성한다. CPU의 **내부 부하 지표**와 **OS 사용률**을 구분해 기술한다.
