# 구현 해설: 실행부터 증거 저장까지

## 1. 구성 요소와 실행 순서

| 파일 | 책임 | 실행 시점 |
| --- | --- | --- |
| `scripts/setup.sh` | ZIP에서 해당 CPU용 실행 파일을 추출하고 필수 환경 구성 | 최초 1회 |
| `scripts/run_case.sh` | 6가지 실험 조건 중 하나를 선택하고 앱/관제 실행 및 종료 | 각 실험마다 |
| `scripts/monitor.sh` | 실행 중인 프로세스 그룹의 PID별 CPU/RSS 수집 | `run_case.sh`가 호출 |

```text
사용자
  ├─ setup.sh → ZIP 검사 → 바이너리 설치 → 디렉터리·key·agent.env
  └─ run_case.sh <장애> <before|after> [초]
       ├─ agent.env 읽기 → 실험 변수 선택 → 포트 사용 여부 확인
       ├─ setsid agent-leak-app 실행 (독립 프로세스 그룹)
       ├─ monitor.sh 병렬 실행 → monitor.tsv
       ├─ 10초마다 ps / 스레드 / 포트 정보 → processes.txt
       └─ 프로그램 종료 또는 제한 시간 도달
            → 마지막 스냅샷 → 관제 종료 → 잔여 프로세스 정리 → result.txt
```

## 2. 준비 과정: `setup.sh`

1. Linux와 **일반 사용자(non-root)** 실행을 확인한다. 앱의 부팅 조건에 해당한다.
2. `uname -m`으로 x86_64/ARM64를 구분하고 ZIP 안에서 실행 파일을 **정확히 하나** 찾는다. 다른 CPU용 실행 파일을 선택하면 실행할 수 없다.
3. `AGENT_HOME` 아래에 `upload_files`, `api_keys`, `logs`를 만든다. 필수 키의 내용은 실습 지정 문자열이며 `chmod 600`으로 소유자만 읽도록 한다.
4. 실행 파일을 복사하고 ZIP 내용과 **SHA-256 해시**가 같은지 검사한다. 다른 ZIP의 오래된 실행 파일을 잘못 사용하는 일을 막는다.
5. 환경변수를 셸이 읽을 수 있는 `agent.env`에 기록한다. `printf '%q'`는 공백 등이 포함된 경로를 이스케이프한다.

> `setup.sh` 성공은 **파일과 환경 준비 성공**이지, 실제 앱이 정상 구동했다는 뜻이 아니다.

## 3. 실험 실행: `run_case.sh`

### 입력·변수 선택

`run_case.sh oom before 50`의 의미는 'OOM의 변경 전 설정으로 최대 50초 동안 관찰'이다. 다른 장애가 결과에 섞이지 않도록 매번 `MEMORY_LIMIT=512`, `CPU_MAX_OCCUPY=40`, `MULTI_THREAD_ENABLE=false`로 초기화한 다음 조사 대상만 바꾼다.

| 실험 | Before | After | 통제하는 변수 |
| --- | --- | --- | --- |
| OOM | MEMORY_LIMIT=256 | MEMORY_LIMIT=512 | CPU=40, 멀티스레드=false |
| CPU | CPU_MAX_OCCUPY=80 | CPU_MAX_OCCUPY=40 | 메모리=512, 멀티스레드=false |
| Deadlock | MULTI_THREAD_ENABLE=true | false | 메모리=512, CPU=40 |

실험값은 **재현을 위한 시도 조건**이다. 실제로 장애가 발생했는지는 반드시 로그로 판단해야 한다.

### 프로세스 시작과 종료

- `setsid "$AGENT_BINARY"`: 새 **세션/프로세스 그룹**에서 앱을 시작한다. 실행 파일이 자식 프로세스를 만들어도 동일한 그룹에 남으면 함께 관찰하고 정리할 수 있다.
- `$!`: 백그라운드로 시작한 실행기의 PID다. 스크립트에서는 이 값을 그룹 ID(`leader`)로 사용한다.
- `group_alive()`: `ps`에서 해당 그룹의 살아 있는 구성원을 찾는다. 종료되어 좀비(`Z`)만 남은 경우에는 살아 있다고 처리하지 않는다.
- `cleanup()`: 모니터를 중단하고, 미종료된 앱 그룹만 `SIGTERM` → 필요 시 `SIGKILL`로 정리한다. **실험기가 강제 종료한 것과 앱 Watchdog이 종료한 것은 구분**해야 한다.
- `trap`: `Ctrl+C`나 오류 등으로 스크립트가 끝날 때에도 `cleanup()`을 실행해 고아 프로세스를 남기지 않는다.

### 저장 파일

| 파일 | 내용과 쓰임 |
| --- | --- |
| `settings.txt` | 실험 변수, UTC 시작 시각, 바이너리 SHA-256 |
| `application.log` | 앱의 표준 출력·오류: MemoryGuard/Watchdog/WAITING 로그 |
| `agent-logs/` | 앱이 `AGENT_LOG_DIR`로 작성하는 추가 로그 |
| `monitor.tsv` | 타임스탬프, PID, 프로세스 상태, RSS(MiB), 구간 CPU(%) |
| `processes.txt` | 10초 간격 PID·TID·대기 채널(`WCHAN`) 및 포트 리스너 |
| `result.txt` | `app_exit` 또는 `observation_limit`, 실행기 종료 코드 |

`result.txt`의 `observation_limit`는 앱이 정상적으로 완료된 것이 아니라 **실험기가 지정 시간 후 종료 요청**을 했다는 뜻이다. 이 경우 `exit_code=143`일 수 있어도 Watchdog SIGTERM의 증거로 사용하면 안 된다. `app_exit`일 때도 실제 원인을 확인하려면 `application.log`가 필요하다.

## 4. 모니터링 계산: `monitor.sh`

1. `ps -eo pid,pgid,stat`에서 실행 그룹에 속한 살아 있는 PID를 찾는다. PID가 여러 개면 **각각 별도로 측정**한다.
2. `/proc/<PID>/stat`에서 사용자 모드 CPU 시간(`utime`, 14번 필드)과 커널 모드 CPU 시간(`stime`, 15번 필드)을 읽고 합한다. `comm` 필드를 먼저 제거하므로 코드 배열에서는 11, 12번 인덱스다.
3. `/proc/<PID>/status`의 `VmRSS`를 읽는다. 단위 KiB를 1024로 나눠 MiB로 변환한다.
4. `/proc/uptime`으로 측정한 실제 경과 시간과 `getconf CLK_TCK`의 초당 CPU tick 수를 사용한다.

\[
\text{CPU 사용률(\%)}=100\times\frac{(\text{현재 ticks}-\text{이전 ticks})/\text{CLK\_TCK}}{\text{경과 시간(초)}}
\]

예: 1초 사이 CPU tick이 75 증가했고 `CLK_TCK=100`이라면 CPU 사용률은 약 75%이다(계산 예시, 실측치 아님). **한 코어를 기준으로 100%**이므로 다중 코어를 사용하는 프로세스는 100%를 넘을 수 있다. 첫 번째 샘플은 차분을 구할 수 없어 `NA`로 표시한다.

PID는 재사용될 수 있으므로 22번 필드의 시작 tick(`starttime`)도 확인한다. 같은 PID라도 시작 tick이 바뀌면 이전 측정치를 이어 붙이지 않는다.

## 5. 실험 판정 방법

- **OOM**: RSS 증가 → `[MemoryGuard] Memory limit exceeded` 등의 앱 로그 → 앱 종료를 연결한다. Linux OOM Killer인지 앱 내부 보호 정책인지 혼동하지 않는다.
- **CPU**: 특정 PID의 CPU 사용률 상승을 `monitor.tsv`에서 확인하고 앱 Watchdog 로그와 대조한다. 앱 로그의 `Current Load`가 OS CPU와 같은 값이라는 가정은 하지 않는다.
- **Deadlock**: PID가 지속 존재하고 앱 로그는 정체되며, 두 스레드가 서로의 자원을 기다리는 `WAITING/BLOCKED` 로그를 확인한다. `WCHAN=futex...`만으로는 교착상태가 입증되지 않는다.
- **Before/After**: 같은 바이너리 해시·환경·관찰 구간을 유지하고 **한 변수만 변경**한 실험 결과를 비교한다. 종료 시각은 `settings.txt`와 `result.txt`의 UTC 시각으로 계산할 수 있다.

## 6. 실제 실행 흐름으로 확인한 증거

실험 시각은 모두 **2026-10-24 UTC**다. 로그에서 받은 종료 이유와 `run_case.sh`가 부여한 종료 이유를 구분한다.

| 호출 | 관측된 앱 실행 흐름 | 종료/판정 | 원본 위치 |
| --- | --- | --- | --- |
| `oom before 45` | `MemoryWorker` Heap 25→275MB, RSS 16.18→266.22MiB | 33초, `MemoryGuard`, `app_exit=137` | [`oom-before`](../evidence/oom-before/) |
| `oom after 50` | Heap 25→400MB, RSS 16.12→416.46MiB | 50초 관찰 후 실험기가 종료 (`143`) | [`oom-after`](../evidence/oom-after/) |
| `cpu before 50` | `CpuWorker` 내부 `Current Load` 5.00→52.07% 및 임계치 위반 | 34초, 앱 종료 `143`. OS CPU 최대 5.94% | [`cpu-before`](../evidence/cpu-before/) |
| `cpu after 50` | 내부 부하 상승과 `Cooldown complete`, MemoryWorker 작업 지속 | 50초 관찰 후 실험기가 종료 | [`cpu-after`](../evidence/cpu-after/) |
| `deadlock before 40` | A→B, B→A 상호 락 대기, PID·TID 존속 및 `futex_wait` | 40초 관찰, 순환 대기 재현 | [`deadlock-before`](../evidence/deadlock-before/) |
| `deadlock after 50` | `Scheduler`가 `All tasks completed.` 기록 | 50초 관찰, 교착 회피 | [`deadlock-after`](../evidence/deadlock-after/) |

**해석상 주의:** CPU 로그의 `Current Load`는 애플리케이션 자체 지표이며 `monitor.tsv`의 Linux `/proc` CPU%와 일치하지 않는다. CPU 실측치와 프로그램 자체 보호 종료를 혼동하거나, 단순히 PID가 존재한다는 이유로 교착을 확정하지 않는다. `result.txt`의 `exit_code=143`은 실험기 SIGTERM에도 나타나므로 반드시 `reason` 및 앱 로그와 교차 확인한다.
